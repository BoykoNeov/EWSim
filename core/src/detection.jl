# detection.jl — Pd / Pfa for a square-law single-pulse detector (HANDOFF §8).
#
# The model: matched-filter output of one pulse, complex Gaussian noise normalised
# to unit power (Re, Im ~ N(0, 1/2)). The detector squares the envelope, z = |x|²,
# and declares a detection when z > Tₕ. With that normalisation noise-only z is
# Exp(1), so the threshold follows from Pfa in closed form and the *signal* power
# is exactly the linear SNR that rf.jl hands us — the two libs compose without a
# units fudge.
#
# Every Pd is computed two ways (HANDOFF §1, the analytic-vs-MC pattern):
#   • analytic    — closed form (Marcum-Q for Swerling 0, exponential for Swerling 1)
#   • monte_carlo — draw noise (+ target fluctuation), threshold, count.
# Their agreement is the first lesson and `test_detection` is the first regression.
# Slice 1 carries Swerling 0 and 1 only; 2–4 land with the CFAR slice (HANDOFF §13).

const _INV_SQRT2 = sqrt(0.5)           # σ of each noise quadrature for unit total power

"""
    detection_threshold(pfa) -> Float64

Square-law detection threshold Tₕ on z = |x|² for a given false-alarm probability.
Noise-only z is Exp(1), so Pfa = P(z > Tₕ) = e^(−Tₕ) ⟹ Tₕ = −ln(Pfa).
"""
detection_threshold(pfa::Real) = -log(pfa)

# --- analytic Pd ----------------------------------------------------------------

# Swerling 0 (non-fluctuating): Pd = Q₁(√(2·SNR), √(2·Tₕ)), the M=1 Marcum-Q.
# Computed from the non-central-χ²(dof 2, λ = 2·SNR) survival in its Poisson-mixture
# form — no Bessel function, hence no SpecialFunctions dependency:
#     Pd = Σ_{j≥0} poisson(j; SNR) · poisscdf(j; Tₕ)
# Both factors are built by incremental multiply (pⱼ = pⱼ₋₁·SNR/j) so nothing
# overflows; the outer Poisson mass we drop bounds the truncation error, since each
# omitted term is ≤ its Poisson weight (poisscdf ≤ 1).
function pd_swerling0(snr::Float64, th::Float64)
    (snr ≥ 0 && th ≥ 0) || throw(DomainError((snr, th), "snr and th must be ≥ 0"))
    pj = exp(-snr)            # outer Poisson(SNR) pmf at j = 0
    ti = exp(-th)             # inner Poisson(Tₕ) pmf at i = 0
    cdf = ti                 # poisscdf(0; Tₕ)
    pd = pj * cdf
    mass = pj                # accumulated outer Poisson mass Σ pⱼ
    j = 0
    jmax = ceil(Int, snr + 60 * sqrt(snr + 1)) + 1000      # safety cap
    while (mass < 1 - 1e-15 || j < snr) && j < jmax
        j += 1
        ti *= th / j         # inner pmf at i = j
        cdf += ti            # poisscdf(j; Tₕ)
        pj *= snr / j        # outer pmf at j
        mass += pj
        pd += pj * cdf
    end
    return clamp(pd, 0.0, 1.0)
end

# Swerling 1 (Rayleigh-fluctuating RCS): for a single pulse the signal is CN(0, SNR),
# so signal+noise is CN(0, 1+SNR) and z is Exp(1+SNR). Hence the closed form
#     Pd = exp(−Tₕ / (1+SNR)) = Pfa^(1/(1+SNR)).
pd_swerling1(snr::Float64, th::Float64) = exp(-th / (1 + snr))

"""
    pd_analytic(snr_lin, pfa; swerling = 1) -> Float64

Closed-form probability of detection for linear SNR `snr_lin` at false-alarm rate
`pfa`. `swerling = 0` is the non-fluctuating target, `1` the Rayleigh case. Both
satisfy Pd → Pfa as SNR → 0 and Pd → 1 as SNR → ∞.
"""
function pd_analytic(snr_lin::Real, pfa::Real; swerling::Integer = 1)
    th = detection_threshold(pfa)
    swerling == 0 && return pd_swerling0(Float64(snr_lin), th)
    swerling == 1 && return pd_swerling1(Float64(snr_lin), th)
    throw(ArgumentError("Swerling $swerling not implemented (slice 1 carries 0 and 1)"))
end

# --- the sampling core (shared by the single-look detector and the MC sweep) -----

# One square-law detector output z = |signal + noise|². Noise quadratures are
# N(0, 1/2) (unit total power). `s0` is the Swerling-0 fixed amplitude √SNR; `sfluc`
# is the σ of each Swerling-1 signal quadrature √(SNR/2) (a fresh CN(0,SNR) draw per
# call). Both amplitudes are passed in precomputed so the MC hot loop never repeats
# a sqrt. The draw order (nI, nQ, then sI, sQ) is fixed — it is part of the RNG
# contract that makes seeded replay bit-identical.
@inline function _sample_z(rng::AbstractRNG, s0::Float64, sfluc::Float64, swerling::Integer)
    nI = randn(rng) * _INV_SQRT2
    nQ = randn(rng) * _INV_SQRT2
    if swerling == 0
        return (s0 + nI)^2 + nQ^2
    else
        sI = randn(rng) * sfluc
        sQ = randn(rng) * sfluc
        return (sI + nI)^2 + (sQ + nQ)^2
    end
end

"""
    detect_once(snr_lin, th, rng; swerling = 1) -> Bool

A single physical detection trial: draw one square-law sample at linear SNR
`snr_lin` and report whether it crosses threshold `th`. This is the honest
realization the live radar uses per look — over many looks the hit fraction
converges to `pd_analytic`. Takes `th` (not `pfa`) so the caller can hoist the
`-log(pfa)` out of a per-tick loop. RNG is explicit, so the look is reproducible.
"""
function detect_once(snr_lin::Real, th::Real, rng::AbstractRNG; swerling::Integer = 1)
    swerling in (0, 1) || throw(ArgumentError("Swerling $swerling not implemented (slice 1 carries 0 and 1)"))
    snr = Float64(snr_lin)
    return _sample_z(rng, sqrt(snr), sqrt(snr / 2), swerling) > th
end

# --- Monte-Carlo Pd -------------------------------------------------------------

"""
    pd_montecarlo(snr_lin, pfa, rng; swerling = 1, trials = 100_000) -> Float64

Estimate Pd by drawing `trials` square-law samples (the same `_sample_z` the live
detector uses) and counting threshold crossings. The RNG is passed in explicitly —
there is no hidden global stream, so the estimate is reproducible from a seed
(HANDOFF determinism invariant). Amplitudes are hoisted out of the loop so it stays
allocation- and sqrt-free.
"""
function pd_montecarlo(snr_lin::Real, pfa::Real, rng::AbstractRNG;
                       swerling::Integer = 1, trials::Integer = 100_000)
    swerling in (0, 1) || throw(ArgumentError("Swerling $swerling not implemented (slice 1 carries 0 and 1)"))
    th = detection_threshold(pfa)
    s0   = sqrt(Float64(snr_lin))        # Swerling 0 signal amplitude
    sfluc = sqrt(Float64(snr_lin) / 2)   # σ of each Swerling 1 signal quadrature
    hits = 0
    for _ in 1:trials
        _sample_z(rng, s0, sfluc, swerling) > th && (hits += 1)
    end
    return hits / trials
end
