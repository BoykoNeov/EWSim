# detection.jl — Pd / Pfa for a square-law detector with N-pulse non-coherent
# integration (HANDOFF §8, §13; slice-3 step 1).
#
# The model: the matched-filter output of one pulse is complex Gaussian noise
# normalised to unit power (Re, Im ~ N(0, 1/2)). The detector squares the envelope,
# z_i = |x_i|², and NON-COHERENTLY integrates N_p pulses: z = Σ_{i=1}^{N_p} z_i,
# declaring a detection when z > Tₕ. With that normalisation noise-only z_i is Exp(1),
# so the integrated noise z is Gamma(N_p, 1) (Erlang) and the threshold follows from
# Pfa in closed form for N_p = 1, by a monotone root-find for N_p > 1. The *signal*
# power is exactly the linear SNR that rf.jl hands us, so the two libs compose with no
# units fudge — the integrated signal power is N_p·SNR.
#
# Approximations, named (HANDOFF §1):
#   • NON-COHERENT integration — magnitudes summed, pulse-to-pulse phase discarded.
#   • Swerling fluctuation drawn per the slow (one RCS sample for the dwell: SW1/SW3)
#     vs fast (independent per pulse: SW2/SW4) model; SW0 is non-fluctuating.
#
# Every Pd is computed two ways (the analytic-vs-MC pattern): a finite/rapidly-
# truncating analytic form and a Monte-Carlo draw of the SAME sampler the live radar
# uses. Their agreement is the lesson and `test_detection` is the regression. At
# N_p = 1 the analytic forms and the sampler collapse to the slice-1 expressions
# exactly (single-pulse SW1 ≡ SW2 and SW3 ≡ SW4) — pinned byte-for-byte so the
# generalization can't silently desync seeded replay.

const _INV_SQRT2 = sqrt(0.5)           # σ of each noise quadrature for unit total power

# --- threshold (Pfa → Tₕ) -------------------------------------------------------

"""
    detection_threshold(pfa, n_pulses = 1) -> Float64

Square-law detection threshold Tₕ on the integrated statistic z = Σ_{i=1}^{N_p}|x_i|²
for a given false-alarm probability. Noise-only z is Gamma(N_p, 1) (Erlang), whose
survival is the finite sum Pfa = P(z > Tₕ) = e^(−Tₕ)·Σ_{k=0}^{N_p−1} Tₕ^k/k!.

`n_pulses = 1` collapses to Exp(1): Tₕ = −ln(Pfa), returned exactly (so the slice-1/2
single-pulse path stays byte-identical). For `n_pulses > 1` the survival has no closed
inverse, so Tₕ is found by bisection on the strictly-decreasing Pfa(T) — hoisted out of
the per-look loop, so a few dozen survival evaluations are free.
"""
function detection_threshold(pfa::Real, n_pulses::Integer = 1)
    p = Float64(pfa)
    n_pulses == 1 && return -log(p)            # slice-1 behavior, exact
    p ≥ 1 && return 0.0                          # Pfa = 1 ⇒ always declare
    N = Int(n_pulses)
    lo = 0.0
    hi = max(1.0, Float64(N))                    # Pfa(0) = 1 ≥ p ≥ Pfa(∞) = 0
    while _erlang_surv(hi, N) > p
        hi *= 2
        hi > 1e7 && break                        # safety; p ≥ 1e-12, N modest ⇒ never hit
    end
    for _ in 1:200
        mid = 0.5 * (lo + hi)
        if _erlang_surv(mid, N) > p
            lo = mid
        else
            hi = mid
        end
        (hi - lo) ≤ 1e-12 * max(1.0, hi) && break
    end
    return 0.5 * (lo + hi)
end

# --- elementary series helpers (no SpecialFunctions) ----------------------------

# Poisson(x) cdf at integer m: e^(−x)·Σ_{i=0}^{m} x^i/i!, built by incremental term
# (tᵢ = tᵢ₋₁·x/i) so nothing overflows. m < 0 ⇒ 0.
function _poisscdf(m::Int, x::Float64)
    m < 0 && return 0.0
    t = exp(-x)
    s = t
    @inbounds for i in 1:m
        t *= x / i
        s += t
    end
    return s
end

# Erlang(m, 1) survival at x: P(Gamma(m,1) > x) = e^(−x)·Σ_{i=0}^{m−1} x^i/i! =
# poisscdf(m−1; x). The forward Pfa(T) for `detection_threshold` and the SW2/SW4 forms.
_erlang_surv(x::Float64, m::Int) = _poisscdf(m - 1, x)

# --- analytic Pd: the slice-1 single-pulse closed forms (kept byte-exact) --------

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

# --- analytic Pd: N-pulse integrated forms (Swerling 0–4) ------------------------

# SLOW / non-fluctuating cases (SW0, SW1, SW3). One RCS sample (or a fixed amplitude)
# is shared by all N_p pulses, so z given the per-dwell power A is non-central
# χ²(2N_p, 2N_p·A); marginalizing A over its fluctuation pdf gives in every case
#     Pd = Σ_{k≥0} w_k · poisscdf(N_p−1+k; Tₕ)
# differing only in the mixing weights w_k (each sequence sums to 1):
#   SW0  Poisson(N_p·SNR):     w_0 = e^(−λ),       w_k = w_{k−1}·λ/k          (λ = N_p·SNR)
#   SW1  geometric (NB r=1):   w_0 = 1−ρ,          w_k = w_{k−1}·ρ            (ρ = λ/(1+λ))
#   SW3  negative-binomial r=2:w_0 = (1−μ)²,       w_k = w_{k−1}·μ·(k+1)/k    (μ = λ/(2+λ))
# (SW0 reduces to `pd_swerling0`, SW1 to exp(−T/(1+SNR)) at N_p=1; both verified.)
#
# The inner poisscdf(N_p−1+k; Tₕ) rises monotonically to 1 as k grows; once it
# saturates, every remaining weight contributes ≈ itself, so the residual sum is the
# leftover weight mass (1 − Σ w_k so far): add it and stop. That bounds the loop to
# ~Tₕ+O(√Tₕ) terms regardless of how slowly the weight tail decays (ρ,μ → 1 at high
# N_p·SNR — the regime a Poisson-sized cap would under-truncate; advisor catch).
function _pd_slow(snr::Float64, th::Float64, n_pulses::Int, swerling::Int)
    λ = n_pulses * snr
    ρ = λ / (1 + λ)
    μ = λ / (2 + λ)
    w = swerling == 0 ? exp(-λ) : swerling == 1 ? (1 - ρ) : (1 - μ)^2

    # inner cdf = poisscdf(N_p−1+k; Tₕ), advanced one Poisson(Tₕ) term per k. Start k=0.
    tj  = exp(-th)
    cdf = tj
    @inbounds for i in 1:(n_pulses - 1)
        tj  *= th / i
        cdf += tj
    end
    m = n_pulses - 1                 # current inner upper index = N_p−1+k

    pd    = 0.0
    wmass = 0.0
    k = 0
    kmax = 1_000_000                 # safety only — the saturation break fires first
    while wmass < 1 - 1e-15 && k < kmax
        if cdf ≥ 1 - 1e-14           # inner cdf saturated ⇒ all remaining w_k see ≈1
            pd += 1 - wmass
            break
        end
        pd    += w * cdf
        wmass += w
        m  += 1                      # advance cdf to N_p−1+(k+1)
        tj *= th / m
        cdf += tj
        k  += 1                      # advance weight to k+1 per the case recurrence
        w *= swerling == 0 ? λ / k : swerling == 1 ? ρ : μ * (k + 1) / k
    end
    return clamp(pd, 0.0, 1.0)
end

# SW2 (fast Rayleigh): independent RCS per pulse ⇒ each z_i ~ Exp(1+SNR), so the
# integrated z ~ Gamma(N_p, 1+SNR) and Pd = ErlangSurv(Tₕ/(1+SNR), N_p). N_p=1 gives
# exp(−Tₕ/(1+SNR)) — exactly `pd_swerling1` (single-pulse SW1 ≡ SW2).
_pd_sw2(snr::Float64, th::Float64, n_pulses::Int) = _erlang_surv(th / (1 + snr), n_pulses)

# SW4 (fast 4-DOF): independent χ²₄ RCS per pulse. The per-pulse MGF M(t) =
# (1−t)/(1−v·t)² (v = 1+SNR/2) factors as a mixture — with prob q=1/v a pulse is
# Gamma(1,v), with prob p=s/v (s=SNR/2) it is Gamma(2,v) — so over N_p independent
# pulses the integrated z is a binomial mixture of Erlangs:
#     Pd = Σ_{j=0}^{N_p} C(N_p,j) p^j q^{N_p−j} · ErlangSurv(Tₕ/v, N_p+j).
# N_p=1 reproduces the single-pulse SW3/SW4 closed form (SW3 ≡ SW4 for one pulse).
function _pd_sw4(snr::Float64, th::Float64, n_pulses::Int)
    s = snr / 2
    v = 1 + s
    p = s / v                        # prob a pulse takes the Gamma(2,v) component
    q = 1 / v                        # prob it takes Gamma(1,v)  (p + q = 1)
    x = th / v
    c = q^n_pulses                   # C(N_p,0)·p^0·q^{N_p}
    pd = 0.0
    @inbounds for j in 0:n_pulses
        pd += c * _erlang_surv(x, n_pulses + j)
        c *= (n_pulses - j) / (j + 1) * (p / q)   # C(N,j+1)/C(N,j)=(N−j)/(j+1), ×p/q
    end
    return clamp(pd, 0.0, 1.0)
end

"""
    pd_analytic(snr_lin, pfa; swerling = 1, n_pulses = 1) -> Float64

Closed-form probability of detection for linear (per-pulse) SNR `snr_lin` at
false-alarm rate `pfa`, with `n_pulses` non-coherently integrated. `swerling ∈ 0:4`
selects the target model: 0 non-fluctuating, 1/2 Rayleigh (slow/fast), 3/4 four-DOF
(slow/fast). Every case satisfies Pd → Pfa as SNR → 0 and Pd → 1 as SNR → ∞.

At `n_pulses = 1` this collapses to the slice-1 expressions (0/1 returned by the exact
`pd_swerling0`/`pd_swerling1`; 2 ≡ 1 and 4 ≡ 3 for a single pulse). The whole point of
integration is that 2 ≠ 1 and 4 ≠ 3 once `n_pulses > 1`.
"""
function pd_analytic(snr_lin::Real, pfa::Real; swerling::Integer = 1, n_pulses::Integer = 1)
    swerling in 0:4 || throw(ArgumentError("Swerling $swerling not implemented (0–4)"))
    n_pulses ≥ 1 || throw(ArgumentError("n_pulses must be ≥ 1 (got $n_pulses)"))
    snr = Float64(snr_lin)
    th  = detection_threshold(pfa, n_pulses)
    if n_pulses == 1
        swerling == 0 && return pd_swerling0(snr, th)     # slice-1, byte-exact
        swerling == 1 && return pd_swerling1(snr, th)      # slice-1, byte-exact
    end
    swerling == 2 && return _pd_sw2(snr, th, Int(n_pulses))
    swerling == 4 && return _pd_sw4(snr, th, Int(n_pulses))
    return _pd_slow(snr, th, Int(n_pulses), Int(swerling))  # 0, 1, 3
end

# --- the sampling core (shared by the single-look detector and the MC sweep) -----

# The signal voltage (sᵢ, sᵩ) added to one pulse's noise. Both amplitudes are passed
# in precomputed (hoisted out of the MC loop, sqrt-free) and exactly as slice-1 spelled
# them, so the N_p=1 draws stay byte-identical: `s0 = √SNR` is the SW0 fixed amplitude,
# `sfluc = √(SNR/2)` is the per-quadrature σ of a CN(0,SNR) draw (NB: √(SNR/2), not
# √SNR·√½ — they differ in the last bit and the slice-1 golden pins the former):
#   SW0       — (√SNR, 0), the same fixed amplitude every pulse (non-fluctuating).
#   SW1/SW2   — CN(0, SNR): each quadrature N(0, SNR/2). 2 draws.
#   SW3/SW4   — four-DOF amplitude, |a|² ~ Gamma(2, SNR/2) = (SNR/4)·χ²₄; the phase is
#               irrelevant (the noise is circular), so a real amplitude suffices. 4 draws.
# The draw counts are fixed by (swerling) alone, so the RNG stream advances identically
# regardless of the SNR *value* (a masked/null target still costs its draws — the
# determinism contract the live radar leans on).
@inline function _draw_signal(rng::AbstractRNG, s0::Float64, sfluc::Float64, swerling::Integer)
    if swerling == 0
        return (s0, 0.0)
    elseif swerling == 1 || swerling == 2
        return (randn(rng) * sfluc, randn(rng) * sfluc)
    else                                                  # 3, 4
        g = 0.0
        @inbounds for _ in 1:4
            r = randn(rng)
            g += r * r
        end
        return (s0 * 0.5 * sqrt(g), 0.0)                  # √((SNR/4)·χ²₄)
    end
end

# One integrated detector statistic z = Σ_{i=1}^{N_p} |signal_i + noise_i|². Noise
# quadratures are N(0, 1/2). The draw ORDER is part of the RNG contract:
#   • fast (SW2/SW4): per pulse draw noise THEN a fresh signal — for N_p=1 this is
#     (nI, nQ, sI, sQ), exactly slice-1.
#   • slow/non-fluctuating (SW0/SW1/SW3): draw all N_p pulses' noise, accumulating
#     ΣnI, ΣnQ, Σ|n|², THEN the one shared amplitude — for N_p=1 the order is again
#     (nI, nQ, [sI, sQ]) and z = (sI+nI)²+(sQ+nQ)², byte-identical to slice-1. The
#     accumulator expands Σ|s+nᵢ|² = N_p|s|² + 2(sI·ΣnI + sᵩ·ΣnQ) + Σ|n|² with no
#     buffer and no second pass.
@inline function _sample_z(rng::AbstractRNG, s0::Float64, sfluc::Float64,
                           swerling::Integer, n_pulses::Integer)
    if swerling == 2 || swerling == 4                     # fast: per-pulse fluctuation
        z = 0.0
        @inbounds for _ in 1:n_pulses
            nI = randn(rng) * _INV_SQRT2
            nQ = randn(rng) * _INV_SQRT2
            sI, sQ = _draw_signal(rng, s0, sfluc, swerling)
            z += (sI + nI)^2 + (sQ + nQ)^2
        end
        return z
    elseif n_pulses == 1                                  # slow, single pulse
        # The slice-1/2 path: draw noise then the (shared) amplitude and square directly.
        # Kept as its own branch so the floating-point operation order is byte-identical
        # to slice 1 — the accumulator below is algebraically equal but rounds the last
        # bit differently, which would break golden replay of an existing scenario.
        nI = randn(rng) * _INV_SQRT2
        nQ = randn(rng) * _INV_SQRT2
        sI, sQ = _draw_signal(rng, s0, sfluc, swerling)
        return (sI + nI)^2 + (sQ + nQ)^2
    else                                                  # slow / non-fluctuating, N_p>1
        SnI = 0.0; SnQ = 0.0; Snn = 0.0
        @inbounds for _ in 1:n_pulses
            nI = randn(rng) * _INV_SQRT2
            nQ = randn(rng) * _INV_SQRT2
            SnI += nI; SnQ += nQ; Snn += nI * nI + nQ * nQ
        end
        sI, sQ = _draw_signal(rng, s0, sfluc, swerling)    # shared amplitude, drawn last
        return n_pulses * (sI * sI + sQ * sQ) + 2 * (sI * SnI + sQ * SnQ) + Snn
    end
end

"""
    detect_once(snr_lin, th, rng; swerling = 1, n_pulses = 1) -> Bool

A single physical detection trial: draw one integrated square-law sample (N_p pulses)
at linear SNR `snr_lin` and report whether it crosses threshold `th`. This is the
honest realization the live radar uses per look — over many looks the hit fraction
converges to `pd_analytic`. Takes `th` (not `pfa`) so the caller can hoist the
threshold out of a per-tick loop. RNG is explicit, so the look is reproducible.
"""
function detect_once(snr_lin::Real, th::Real, rng::AbstractRNG;
                     swerling::Integer = 1, n_pulses::Integer = 1)
    swerling in 0:4 || throw(ArgumentError("Swerling $swerling not implemented (0–4)"))
    n_pulses ≥ 1 || throw(ArgumentError("n_pulses must be ≥ 1 (got $n_pulses)"))
    snr = Float64(snr_lin)
    return _sample_z(rng, sqrt(snr), sqrt(snr / 2), swerling, n_pulses) > th
end

# --- Monte-Carlo Pd -------------------------------------------------------------

"""
    pd_montecarlo(snr_lin, pfa, rng; swerling = 1, n_pulses = 1, trials = 100_000) -> Float64

Estimate Pd by drawing `trials` integrated square-law samples (the same `_sample_z`
the live detector uses) and counting threshold crossings. The RNG is passed in
explicitly — there is no hidden global stream, so the estimate is reproducible from a
seed (HANDOFF determinism invariant). The √SNR amplitude is hoisted out of the loop so
it stays allocation- and (constant-)sqrt-free.
"""
function pd_montecarlo(snr_lin::Real, pfa::Real, rng::AbstractRNG;
                       swerling::Integer = 1, n_pulses::Integer = 1, trials::Integer = 100_000)
    swerling in 0:4 || throw(ArgumentError("Swerling $swerling not implemented (0–4)"))
    n_pulses ≥ 1 || throw(ArgumentError("n_pulses must be ≥ 1 (got $n_pulses)"))
    th = detection_threshold(pfa, n_pulses)
    snr   = Float64(snr_lin)
    s0    = sqrt(snr)            # SW0 amplitude
    sfluc = sqrt(snr / 2)        # σ of each SW1/SW2 signal quadrature
    hits = 0
    for _ in 1:trials
        _sample_z(rng, s0, sfluc, swerling, n_pulses) > th && (hits += 1)
    end
    return hits / trials
end
