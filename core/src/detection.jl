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

# --- CFAR adaptive thresholding (slice-3 step 2) --------------------------------
#
# A range-power profile is a vector of LINEAR-power range cells (noise-only cells are
# Gamma(N_p, 1) — Exp(1) at N_p = 1). CFAR sets each cell's detection threshold from the
# training cells AROUND the cell-under-test (CUT): T = α · (noise estimate), with the
# variant choosing the estimator and α calibrated so the homogeneous-noise false-alarm
# rate equals the design Pfa. The threshold CURVE is the core output the client renders
# (never recomputed in GDScript — HANDOFF §1). Everything here is PURE: no RNG, so a scan
# can never desync a seeded trace (the profile draw itself lives in radar.jl, slice-3 step 3).
#
# Approximations, named (HANDOFF §1):
#   • 1-D range-only window — training cells are neighbours in RANGE only (no Doppler).
#   • Closed-form α is exact for EXPONENTIAL cells (N_p = 1) for every variant, and for
#     GAMMA cells (N_p > 1) only for CA (the exact Beta form below). GO/SO/OS over Gamma
#     cells have no finite-sum inverse, so they are N_p = 1 only here; the integrated
#     CA path is the one validated against Monte-Carlo Pfa-maintenance (slice-3 plan,
#     Decisions — "all closed forms at N_p=1; N_p>1 by MC").
#   • Edge cells (window truncated at the array ends) shrink the training set and reuse
#     the interior α; design Pfa is maintained only in the interior (where the full
#     window fits). The estimator simply averages/orders whatever cells are in bounds —
#     it never indexes out of bounds (the slice-3 edge watch-item).
#
# Convention — the byte-identity contract across `cfar_alpha`, `cfar_threshold` and the
# MC test (the advisor's bug-magnet): the noise estimate and α are both in the MEAN
# convention. For CA the estimate is the MEAN of the N training cells and α multiplies
# that mean; the closed forms below all encode that mean (the factor N). Pairing a
# sum-estimate with a mean-α (or vice-versa) is off by a factor of N — so the MC test
# calls the SAME estimator, never a re-spelling.

# The CFAR rungs this library knows. `:fixed` is the non-adaptive baseline (a flat
# `detection_threshold` laid over the profile — NOT the legacy point detector); the rest
# are windowed. radar.jl's `CFAR_MODES` (slice-3 step 3) is the wire source of truth and
# will mirror this set.
const CFAR_VARIANTS = (:fixed, :ca, :go, :so, :os)

# Default OS rank: the k-th smallest of the N training cells, k ≈ 0.75·N (Rohling).
_os_default_k(n_train::Int) = clamp(round(Int, 0.75 * n_train), 1, n_train)

# P(Beta(a, b) > w) for integer shapes a, b ≥ 1 — the regularized incomplete Beta tail as
# a FINITE binomial sum (no SpecialFunctions): Σ_{j=0}^{a−1} C(M,j) w^j (1−w)^{M−j},
# M = a+b−1. This is the EXACT CA-CFAR Pfa over Gamma(N_p,1) cells: the CUT is Gamma(N_p,1),
# the training sum is Gamma(N·N_p,1), and their ratio crosses the Beta(N_p, N·N_p) tail at
# w = α/(N+α). At a = 1 it collapses to (1−w)^b = (1+α/N)^{−N}, the N_p=1 CA form. Terms are
# built by the C(M,j)/C(M,j−1) = (M−j+1)/j ratio so nothing overflows.
function _beta_surv_int(w::Float64, a::Int, b::Int)
    M = a + b - 1
    om = 1 - w
    term = om^M                              # j = 0
    s = term
    @inbounds for j in 1:(a - 1)
        term *= (M - j + 1) / j * (w / om)
        s += term
    end
    return s
end

"""
    _cfar_pfa(variant, α, n_train; n_pulses = 1, k = ⌈0.75·n_train⌋) -> Float64

Forward homogeneous-noise Pfa(α) for a CFAR variant — the closed form that [`cfar_alpha`]
(@ref) inverts and the ordering-invariant test pins. Strictly decreasing in α (Pfa(0)=1,
Pfa(∞)=0). All N_p = 1 except CA, which is exact for all N_p via the Beta tail:

  • CA  exponential (N_p=1):  `(1 + α/N)^(−N)`                       (mean-of-N MGF)
        gamma (N_p>1):        `BetaSurv(α/(N+α); N_p, N·N_p)`        ([`_beta_surv_int`](@ref))
  • OS  (N_p=1):              `∏_{i=0}^{k−1} (N−i)/(N−i+α)`          (Rohling product)
  • SO  (N_p=1, M=N/2):       `2 Σ_{j=0}^{M−1} C(M−1+j,j) (2+α/M)^(−(M+j))`
  • GO  (N_p=1, M=N/2):       `2 (1+α/M)^(−M) − Pfa_SO`             (E[e^{−s·max}] via max+min)
"""
function _cfar_pfa(variant::Symbol, α::Float64, n_train::Int;
                   n_pulses::Int = 1, k::Int = _os_default_k(n_train))
    N = n_train
    if variant === :ca
        return n_pulses == 1 ? (1 + α / N)^(-N) :
                               _beta_surv_int(α / (N + α), n_pulses, N * n_pulses)
    elseif variant === :os
        n_pulses == 1 || throw(ArgumentError(
            "OS-CFAR closed form is N_p=1 only (got n_pulses=$n_pulses); the integrated path is MC-validated"))
        p = 1.0
        @inbounds for i in 0:(k - 1)
            p *= (N - i) / (N - i + α)
        end
        return p
    elseif variant === :so || variant === :go
        n_pulses == 1 || throw(ArgumentError(
            "$(uppercase(string(variant)))-CFAR closed form is N_p=1 only (got n_pulses=$n_pulses); the integrated path is MC-validated"))
        iseven(N) || throw(ArgumentError("GO/SO closed form needs an even n_train (two equal halves); got $N"))
        M  = N ÷ 2
        b  = 2 + α / M
        pw = b^(-M)                          # (2+α/M)^(−(M+j)), starting j = 0
        c  = 1.0                             # C(M−1+j, j), starting j = 0
        so = 0.0
        @inbounds for j in 0:(M - 1)
            so += c * pw
            c  *= (M + j) / (j + 1)          # C(M+j, j+1)/C(M−1+j, j) = (M+j)/(j+1)
            pw /= b
        end
        pfa_so = 2 * so
        return variant === :so ? pfa_so : 2 * (1 + α / M)^(-M) - pfa_so
    else
        throw(ArgumentError("CFAR variant :$variant has no closed-form Pfa (use :ca, :go, :so or :os)"))
    end
end

# Invert a strictly-decreasing Pfa(α) (Pfa(0)=1, Pfa(∞)=0) for the α giving design `pfa`.
# Same bracket-then-bisect idiom as `detection_threshold` (no SpecialFunctions, no deps).
function _bisect_alpha(pfa_of_alpha, pfa::Float64)
    pfa ≥ 1 && return 0.0                     # Pfa = 1 ⇒ no margin needed
    lo = 0.0
    hi = 1.0
    while pfa_of_alpha(hi) > pfa
        hi *= 2
        hi > 1e12 && break                    # safety; pfa ≥ 1e-12, N modest ⇒ never hit
    end
    for _ in 1:200
        mid = 0.5 * (lo + hi)
        if pfa_of_alpha(mid) > pfa
            lo = mid
        else
            hi = mid
        end
        (hi - lo) ≤ 1e-12 * max(1.0, hi) && break
    end
    return 0.5 * (lo + hi)
end

"""
    cfar_alpha(variant, n_train, pfa; n_pulses = 1, k = ⌈0.75·n_train⌋) -> Float64

The CFAR threshold multiplier α such that `T = α · (noise estimate)` holds the design
false-alarm probability `pfa` in homogeneous noise. `variant ∈ (:ca, :go, :so, :os)`
(`:fixed` has no window/α — see [`cfar_scan`](@ref)). Inverts the monotone
[`_cfar_pfa`](@ref):

  • CA, N_p=1: returns the exact `α = N·(pfa^(−1/N) − 1)` directly (the test anchor;
    `N → ∞` ⇒ `−ln(pfa)`, i.e. the CFAR loss vanishes as the estimate sharpens).
    CA, N_p>1: bisects the exact Beta form.
  • OS / SO / GO: bisect their finite-sum Pfa(α). `n_pulses > 1` is rejected for these
    (no finite-sum inverse over Gamma cells; the integrated path is MC-validated).
"""
function cfar_alpha(variant::Symbol, n_train::Integer, pfa::Real;
                    n_pulses::Integer = 1, k::Integer = _os_default_k(Int(n_train)))
    N  = Int(n_train)
    np = Int(n_pulses)
    p  = Float64(pfa)
    N ≥ 1  || throw(ArgumentError("n_train must be ≥ 1 (got $N)"))
    np ≥ 1 || throw(ArgumentError("n_pulses must be ≥ 1 (got $np)"))
    variant === :ca && np == 1 && return N * (p^(-1 / N) - 1)        # exact closed form
    return _bisect_alpha(a -> _cfar_pfa(variant, a, N; n_pulses = np, k = Int(k)), p)
end

# Mean of the whole profile — the fallback noise estimate when a cell's window is fully
# truncated (profile shorter than the window). Finite and positive (cells are powers > 0);
# only reached on pathologically short profiles — the interior never uses it.
_global_mean(profile::AbstractVector{<:Real}) = sum(profile) / length(profile)

# Per-cell noise estimate for a windowed variant. Training cells = the `n_half` on each
# side of `cut`, skipping `n_guard` guard cells, CLAMPED to the array bounds (edges shrink
# the set; never out-of-bounds). `buf` (length ≥ n_train) backs the OS order-statistic
# without a per-cell allocation; CA/GO/SO ignore it.
function _cfar_estimate(profile::AbstractVector{<:Real}, cut::Int, variant::Symbol,
                        n_half::Int, n_guard::Int, k::Int, buf::Vector{Float64})
    L = length(profile)
    l_lo = max(1, cut - n_guard - n_half); l_hi = min(L, cut - n_guard - 1)
    r_lo = max(1, cut + n_guard + 1);      r_hi = min(L, cut + n_guard + n_half)
    sL = 0.0; nL = 0
    @inbounds for i in l_lo:l_hi
        sL += profile[i]; nL += 1
    end
    sR = 0.0; nR = 0
    @inbounds for i in r_lo:r_hi
        sR += profile[i]; nR += 1
    end
    ntot = nL + nR
    if variant === :ca
        ntot == 0 && return _global_mean(profile)
        return (sL + sR) / ntot
    elseif variant === :go || variant === :so
        nL == 0 && nR == 0 && return _global_mean(profile)
        nL == 0 && return sR / nR
        nR == 0 && return sL / nL
        mL = sL / nL; mR = sR / nR
        return variant === :go ? max(mL, mR) : min(mL, mR)
    elseif variant === :os
        ntot == 0 && return _global_mean(profile)
        idx = 0
        @inbounds for i in l_lo:l_hi; idx += 1; buf[idx] = profile[i]; end
        @inbounds for i in r_lo:r_hi; idx += 1; buf[idx] = profile[i]; end
        return partialsort!(view(buf, 1:ntot), clamp(k, 1, ntot))
    else
        throw(ArgumentError("CFAR variant :$variant not one of $(CFAR_VARIANTS)"))
    end
end

"""
    cfar_threshold(profile, cut; variant=:ca, n_train, n_guard=0, pfa, n_pulses=1, k=…) -> Float64

The adaptive detection threshold (LINEAR power) for the cell-under-test `cut` of a
range-power `profile`: `α · (noise estimate)` with α from [`cfar_alpha`](@ref) and the
estimator chosen by `variant`. `:fixed` ignores the window and returns the flat
`detection_threshold(pfa, n_pulses)`. Pure — no RNG. Windowed variants need an even
`n_train` (N/2 training cells per side).
"""
function cfar_threshold(profile::AbstractVector{<:Real}, cut::Integer;
                        variant::Symbol = :ca, n_train::Integer, n_guard::Integer = 0,
                        pfa::Real, n_pulses::Integer = 1,
                        k::Integer = _os_default_k(Int(n_train)))
    variant === :fixed && return detection_threshold(pfa, n_pulses)
    N = Int(n_train)
    iseven(N) || throw(ArgumentError("n_train must be even (N/2 per side); got $N"))
    α   = cfar_alpha(variant, N, pfa; n_pulses = n_pulses, k = k)
    buf = variant === :os ? Vector{Float64}(undef, N) : Float64[]
    est = _cfar_estimate(profile, Int(cut), variant, N ÷ 2, Int(n_guard), Int(k), buf)
    return α * est
end

"""
    cfar_scan(profile; variant=:ca, n_train, n_guard=0, pfa, n_pulses=1, k=…)
        -> (threshold, detections)

Run CFAR over an entire range-power `profile` (LINEAR power). Returns the per-cell
`threshold::Vector{Float64}` curve (the CORE output the client renders — never recomputed
downstream) and `detections::Vector{Bool}` (`profile[i] > threshold[i]`). PURE — no RNG,
so a scan can never desync a seeded trace. One α is computed for the full window and
reused at every cell; edge cells shrink the training set (design Pfa held only in the
interior — see the module notes). `:fixed` lays a flat `detection_threshold` over the
profile (the "before CFAR" baseline, NOT the legacy point detector). Windowed variants
need an even `n_train`.
"""
function cfar_scan(profile::AbstractVector{<:Real};
                   variant::Symbol = :ca, n_train::Integer, n_guard::Integer = 0,
                   pfa::Real, n_pulses::Integer = 1,
                   k::Integer = _os_default_k(Int(n_train)))
    L = length(profile)
    threshold = Vector{Float64}(undef, L)
    if variant === :fixed
        fill!(threshold, detection_threshold(pfa, n_pulses))
    else
        variant in CFAR_VARIANTS || throw(ArgumentError("CFAR variant :$variant not one of $(CFAR_VARIANTS)"))
        N = Int(n_train)
        iseven(N) || throw(ArgumentError("n_train must be even (N/2 per side); got $N"))
        nh  = N ÷ 2
        ng  = Int(n_guard)
        kk  = Int(k)
        α   = cfar_alpha(variant, N, pfa; n_pulses = n_pulses, k = kk)
        buf = variant === :os ? Vector{Float64}(undef, N) : Float64[]
        @inbounds for cut in 1:L
            threshold[cut] = α * _cfar_estimate(profile, cut, variant, nh, ng, kk, buf)
        end
    end
    detections = Vector{Bool}(undef, L)
    @inbounds for i in 1:L
        detections[i] = profile[i] > threshold[i]
    end
    return (threshold, detections)
end
