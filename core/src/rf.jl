# rf.jl — radar equation / link budget (HANDOFF §5, §8).
#
# Pure phenomenology: SNR from the radar range equation, never carrier-frequency
# samples (HANDOFF §1 — work at link-budget level). No geometry or entities here;
# the radar *subsystem* (step 5) computes range and feeds it in. Everything is SI
# Float64. dB ⇄ linear conversions live here because this is where the boundary is.

const C_LIGHT     = 299_792_458.0      # m/s, speed of light (exact, SI)
const K_BOLTZMANN = 1.380649e-23       # J/K, Boltzmann constant (exact, SI 2019)
const T0_REF      = 290.0              # K, IEEE reference noise temperature

"Decibels → linear power ratio."
db2lin(db) = 10.0 ^ (db / 10.0)
"Linear power ratio → decibels."
lin2db(x)  = 10.0 * log10(x)

"Carrier wavelength λ = c / f, metres."
wavelength(freq_hz) = C_LIGHT / freq_hz

"""
    RadarParams(pt_w, gain_db, freq_hz, bandwidth_hz, noise_fig_db, losses_db)

The transmit/receive chain of one monostatic radar, as it appears in a scenario's
`radar:` block. Gain, noise figure and losses are carried in dB (how data sheets
quote them) and converted at use. `freq_hz` enters only through λ — we never
simulate at the carrier.
"""
struct RadarParams
    pt_w::Float64          # peak transmit power, W
    gain_db::Float64       # antenna gain, one-way, dB (squared for monostatic Tx·Rx)
    freq_hz::Float64       # carrier frequency, Hz (used only for λ)
    bandwidth_hz::Float64  # receiver / matched-filter noise bandwidth, Hz
    noise_fig_db::Float64  # receiver noise figure, dB (≥ 0)
    losses_db::Float64     # lumped system losses, dB (≥ 0)
end

"""
    snr_freespace(rp::RadarParams, rcs_m2, range_m) -> Float64   (linear)

Single-pulse signal-to-noise ratio from the monostatic free-space radar equation:

    SNR = Pt · G² · λ² · σ / ( (4π)³ · R⁴ · k · T0 · B · F · L )

The R⁴ law (two-way spreading) is the headline behaviour: doubling range costs
~12 dB. `free_space` is the first rung of the `propagation` fidelity ladder —
`two_ray` lands later behind the same knob (HANDOFF §10).
"""
function snr_freespace(rp::RadarParams, rcs_m2::Real, range_m::Real)
    range_m > 0 || throw(DomainError(range_m, "range must be > 0"))
    G = db2lin(rp.gain_db)
    F = db2lin(rp.noise_fig_db)
    L = db2lin(rp.losses_db)
    λ = wavelength(rp.freq_hz)
    num = rp.pt_w * G^2 * λ^2 * rcs_m2
    den = (4π)^3 * range_m^4 * K_BOLTZMANN * T0_REF * rp.bandwidth_hz * F * L
    return num / den
end

"Single-pulse SNR in dB (see [`snr_freespace`](@ref))."
snr_db_freespace(rp::RadarParams, rcs_m2::Real, range_m::Real) =
    lin2db(snr_freespace(rp, rcs_m2, range_m))

# --- two_ray: flat-earth multipath + 4/3-Earth horizon (HANDOFF §10, slice 2) ---
#
# The second rung of the `propagation` fidelity ladder. `free_space` ignores the
# ground entirely (infinite LOS, no multipath); `two_ray` introduces a flat
# reflecting plane → interference lobing, and a curved-earth horizon → masking.
# Three named approximations, all switchable by the one `propagation` knob:
#   • flat-earth small-grazing phase  (path difference ΔR ≈ 2·h_r·h_t / R_g)
#   • ρ = −1 perfect reflection       (horizontal pol at grazing; the default)
#   • 4/3-Earth radar horizon         (standard-atmosphere refraction, k = 4/3)
# Everything is the SNR *modulation*; the detector (detection.jl) is untouched.

const R_EARTH    = 6.371e6   # m, mean Earth radius (geometric horizon)
const K_FOURTHIRDS = 4 / 3   # standard-atmosphere effective-radius factor

"""
    two_ray_phase(λ, h_r, h_t, ground_m) -> Δφ   (radians)

Phase difference between the ground-reflected and direct rays,

    Δφ = 4π·h_r·h_t / (λ·R_g)

from the **flat-earth small-grazing approximation** to the path-length difference
ΔR ≈ 2·h_r·h_t / R_g (valid when both antenna heights ≪ ground range `R_g`).
`h_r`, `h_t` are heights above the reflecting plane; `ground_m` is the horizontal
(ground) range. Degenerate by design: either height → 0 sends Δφ → 0, i.e. the
target sits in a perpetual null (see [`snr_two_ray`](@ref)).
"""
two_ray_phase(λ::Real, h_r::Real, h_t::Real, ground_m::Real) =
    4π * h_r * h_t / (λ * ground_m)

"""
    two_ray_factor4(Δφ; refl=-1.0) -> F⁴   (linear, two-way power)

Two-way (monostatic) pattern-propagation factor for one flat-earth reflected ray:

    F² = |1 + ρ·e^{-iΔφ}|² = 1 + ρ² + 2ρ·cos Δφ     (one-way power)
    F⁴ = (F²)²                                        (out-and-back)

With **ρ = −1 perfect reflection** this collapses to F⁴ = (2 − 2cos Δφ)² =
16·sin⁴(Δφ/2): peak 16 (+12.04 dB at a lobe) and exact nulls (0) where the rays
cancel. With ρ = 0 (no ground) F⁴ ≡ 1, recovering free space exactly.
"""
two_ray_factor4(Δφ::Real; refl::Real = -1.0) = (1 + refl^2 + 2 * refl * cos(Δφ))^2

"""
    snr_two_ray(rp, rcs_m2, slant_m; h_r, h_t, ground_m, refl=-1.0) -> Float64  (linear)

Single-pulse SNR with flat-earth two-ray multipath:

    SNR_two_ray = SNR_freespace(R_slant) · F⁴(Δφ)

The link budget (R⁴ spreading) is evaluated at the true **slant** range `slant_m`;
the multipath modulation `F⁴` uses the **ground** range `ground_m` and the antenna
heights `h_r`, `h_t` (height above the reflecting plane). At small grazing angles
F⁴ ∝ R_g⁻⁴, so the SNR envelope falls as R⁻⁸ (−24.08 dB per range-doubling), the
two-ray signature. With `refl = 0` this returns exactly [`snr_freespace`](@ref).

Approximations (HANDOFF §1 — named, not hidden): flat-earth small-grazing phase,
ρ = −1 perfect reflection (overridable via `refl`). **Horizon masking is NOT
applied here** — this is pure phenomenology; the radar subsystem decides the
below-horizon policy (finite floor / `visible:false`) using [`horizon_range`](@ref).
"""
function snr_two_ray(rp::RadarParams, rcs_m2::Real, slant_m::Real;
                     h_r::Real, h_t::Real, ground_m::Real, refl::Real = -1.0)
    ground_m > 0 || throw(DomainError(ground_m, "ground range must be > 0"))
    λ  = wavelength(rp.freq_hz)
    Δφ = two_ray_phase(λ, h_r, h_t, ground_m)
    F4 = two_ray_factor4(Δφ; refl = refl)
    return snr_freespace(rp, rcs_m2, slant_m) * F4
end

"Single-pulse two-ray SNR in dB (see [`snr_two_ray`](@ref))."
snr_db_two_ray(rp::RadarParams, rcs_m2::Real, slant_m::Real; kwargs...) =
    lin2db(snr_two_ray(rp, rcs_m2, slant_m; kwargs...))

"""
    horizon_range(h_r, h_t; k=4/3, r_earth=R_EARTH) -> Float64   (metres)

Radar horizon under the **4/3-Earth** approximation (standard-atmosphere
refraction bends the ray, modelled as a straight ray over an Earth of effective
radius k·R_e):

    d_horizon = √(2·k·R_e)·(√h_r + √h_t)  ≈ 4121.8·(√h_r + √h_t)   (k = 4/3)

A target whose **ground** range exceeds this is below the line of sight and masked.
Heights are above the reflecting plane.
"""
horizon_range(h_r::Real, h_t::Real; k::Real = K_FOURTHIRDS, r_earth::Real = R_EARTH) =
    sqrt(2 * k * r_earth) * (sqrt(h_r) + sqrt(h_t))
