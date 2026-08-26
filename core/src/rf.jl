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

# --- slice 46: THE APERTURE AND THE HORIZON (a sensor's REACH, and what it costs) -------------
#
# Slices 32/34 gave the missile seeker a WINDOW and stopped there: "can the seeker see it?" was
# modelled as an ANGLE question alone. The other half is the link budget — past some range the
# echo is under the receiver's threshold and there is no measurement at whatever angle. ⭐ AND THE
# TWO HALVES ARE THE SAME DESIGN VARIABLE PULLING OPPOSITE WAYS: the window IS the beamwidth, the
# beamwidth sets the aperture, the aperture sets the gain, and the gain sets the reach —
# `R_acq · fov = constant` (MEASURED to 0.0000 % on the flying wire, `docs/plans/slice44.md`).
# A wider window buys coverage and pays for it in range, and neither is free.
#
# ⚠ NOTHING HERE IS SEEKER-SPECIFIC (convention 12): any antenna has an aperture and any receiver
# has a threshold. The SEEKER's coupling — that its detector window is the beamwidth that implies
# its gain — is built in `missile.jl`, where the entities and the window live.

"""
    aperture_gain(beamwidth_rad; eta = 0.6) -> Float64   (linear power gain)

**THE APERTURE IDENTITY.** An antenna that concentrates its power into a solid angle `Ω` has gain
`G = η · 4π / Ω` over an isotropic radiator — the whole content of "gain" as the radar equation
uses it. For a beam of full width `θ` on each of two axes, `Ω ≈ θ²`.

`beamwidth_rad` is the **FULL** beamwidth, not the half-angle: a detector window quoted as
"`fov` degrees off the axis" (the `seeker_in_fov` / `gimbal_fov_deg` posture) is a HALF-angle and
enters here as `2·fov`. Getting that factor wrong is a 4× error in gain, i.e. 6 dB, i.e. 41 % in
range — so the unit is in the argument name and the conversion is the caller's, once.

`eta` is aperture efficiency (illumination taper, spillover, blockage); 0.5–0.7 is the usual range
for a real dish and 0.6 is the conventional book value.

⚠ Non-positive `beamwidth_rad` throws: a zero-width beam is an infinite gain, and convention 6
(no Inf/NaN to JSON) is a floor downstream of a DomainError here, not a substitute for it.
"""
function aperture_gain(beamwidth_rad::Real; eta::Real = 0.6)
    beamwidth_rad > 0 || throw(DomainError(beamwidth_rad, "beamwidth must be > 0"))
    eta > 0 || throw(DomainError(eta, "aperture efficiency must be > 0"))
    θ = Float64(beamwidth_rad)
    return Float64(eta) * 4π / (θ * θ)
end

"""
    aperture_diameter(freq_hz, beamwidth_rad) -> Float64   (m)

The circular aperture that produces that beamwidth, from the standard uniform-illumination
relation `θ_3dB ≈ 1.02 λ / D`. **A READOUT, not a model input** — nothing in the link budget reads
it — but it is the number that tells a student whether the seeker they just authored would fit in
the missile they are flying (an 18.7 mm λ at a 20° full beamwidth is a 5.4 cm dish; at 2° it is
54 cm, which is not going in a small air-to-air airframe).
"""
function aperture_diameter(freq_hz::Real, beamwidth_rad::Real)
    beamwidth_rad > 0 || throw(DomainError(beamwidth_rad, "beamwidth must be > 0"))
    return 1.02 * wavelength(freq_hz) / Float64(beamwidth_rad)
end

"""
    detection_range(rp::RadarParams, rcs_m2; snr_min_db = 10.0) -> Float64   (m)

**THE HORIZON.** The range at which [`snr_freespace`](@ref) falls to `snr_min_db` — inside it the
echo clears the threshold, outside it there is no detection at any angle.

Because the free-space SNR is exactly `K / R⁴`, the inverse is closed-form:

    K = SNR·R⁴ = snr_freespace(rp, σ, 1.0)   ⇒   R_acq = (K / snr_min)^(1/4)

⭐ `K` is READ FROM `snr_freespace` AT UNIT RANGE, never re-derived (the [`burnthrough_range`](@ref)
posture): any slip in the link budget moves the horizon in LOCKSTEP with the SNR the detector
actually sees, instead of drifting from it. The ¼ power is the R⁴ law's revenge — **16× the
transmit power buys 2× the range**, which is why reach is bought with aperture and integration
rather than with a bigger transmitter.

⚠ DETERMINISTIC — a hard threshold, no `Pd` draw and no RNG. That is what keeps a detection gate
built on it in convention 4's class (c): physics-changing, draw-topology-invariant.
"""
function detection_range(rp::RadarParams, rcs_m2::Real; snr_min_db::Real = 10.0)
    rcs_m2 > 0 || throw(DomainError(rcs_m2, "RCS must be > 0"))
    K = snr_freespace(rp, rcs_m2, 1.0)          # = SNR·R⁴, the link budget's own constant
    return (K / db2lin(snr_min_db)) ^ 0.25
end

"""
    SEEKER_DETECT_MODES

The `:seeker_detect` fidelity's rungs — **whether the seeker's availability verdict consults the
LINK BUDGET at all** (slice 46):

* `:none` — an ANGLE-ONLY seeker (slices 11–45). If the target is inside the detector window it is
  measured, at any range. The DEFAULT, and every scenario predating this slice is bit-for-bit
  unchanged under it — the seam's conjunct is the literal `true`.
* `:snr`  — the echo must also clear the receiver's threshold: no measurement past
  [`detection_range`](@ref), at whatever angle.

⚠ The rung lives HERE, beside the budget it selects, for convention 7's reason (defined once,
referenced everywhere) — `radar.jl`'s `LIVE_FIDELITY_MODES` and `scenario.jl`'s loader both name this
tuple rather than re-spelling the pair. ⚠ Both rungs are DETERMINISTIC (a hard threshold, no `Pd`
draw), so this is convention 4's class (c): physics-changing with NO RNG, draw-topology invariant,
and therefore live-settable with no `set_fidelity` guard.
"""
const SEEKER_DETECT_MODES = (:none, :snr)

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

"""
    rcs_aspect(rcs_broadside_m2, fineness, aspect_rad) -> Float64   (m²)

**HOW VISIBLE YOU ARE DEPENDS ON WHICH WAY YOU ARE POINTING** (slice 49). The physical-optics
radar cross-section of a body of revolution, NORMALIZED to its broadside value:

    σ(θ) = σ_broadside / (sin²θ + F²·cos²θ)²

`θ` is the ASPECT ANGLE (radians) — the angle at the target between its own nose and the
direction of the observer, so `θ = 0` is nose-on, `π/2` broadside, `π` tail-on
([`aspect_angle`](@ref) forms it, and owns the sign). `F` is the **FINENESS RATIO** `L/r`, the
dimensionless slenderness of the body: how many times longer than wide.

This is the standard high-frequency ellipsoid `σ = π a²b²c² / (a²sin²θcos²φ + b²sin²θsin²φ +
c²cos²θ)²` for a body of revolution, divided through by its own `θ = π/2` value. ⭐ **THE
NORMALIZATION IS THE DESIGN DECISION, NOT A COSMETIC ONE.** The raw form fixes σ from the axes
alone — a 5 m × 0.5 m body gives σ_broadside = πL² = 78.5 m², which is ~4000× what
`scenarios/slice48_search.yaml` deliberately authors. The arc's `rcs_m2` values are TUNING
numbers for where a horizon should sit, and a model that overrides them is a model no existing
scenario can carry. Normalized, `rcs_m2` keeps its authored meaning and gains a sharper one — it
is the BROADSIDE RCS — and exactly ONE new number is authored, with a physical name.

Three anchors, all hand-checkable (convention 11's EXTERNAL anchor, pinned in
`test_rcs_aspect.jl`):

* `θ = π/2` (broadside) ⇒ σ ≡ `σ_broadside`, **exactly**, at every `F`.
* `θ = 0` or `π` (nose/tail) ⇒ σ = `σ_broadside / F⁴`. F = 10 is **40 dB** down, the right order
  for a real airframe.
* `F = 1` (a sphere) ⇒ σ ≡ `σ_broadside` at every angle — aspect-independent, the NULL.

⚠⚠ **THE FOURTH-ROOT REFLEX IS A TRAP HERE, AND IT COST THIS SLICE A WRONG PREDICTION.**
[`detection_range`](@ref) goes as σ^(1/4), so "a 40 dB swing is only 10× in range" invites the
conclusion that aspect is negligible. It is not: this denominator is SQUARED, so for a slender
body the `F²cos²θ` term dominates until θ is very near broadside, and σ moves 40× over the 17°
between 65° and 82°. The `^(1/4)` going out and the `^2` coming in very nearly cancel. See
`docs/plans/slice49.md` §2.

⚠ **FORE/AFT SYMMETRY IS A NAMED APPROXIMATION** (HANDOFF §1): σ(θ) ≡ σ(π−θ), so a fleeing
target looks exactly like an approaching one. Real airframes have a distinct tail return
(engine / exhaust). A tail lobe is a deferral, not a defect.

⚠ **DOMAIN.** `σ_broadside > 0` and `F > 0` throw `DomainError` by design — the
[`detection_range`](@ref) posture, clamped at the CONSUMER (convention 5), never here.
`F < 1` is legal and is an OBLATE body (wider than long — brighter nose-on than broadside);
the formula handles it and the units stay honest.

⚠⚠ **DO NOT USE `F = 1` AS THE BYTE-IDENTITY PATH.** `sin²θ + cos²θ` is 1 in algebra and not
always 1.0 in floating point, so a scalar-RCS wire must branch PAST this call entirely (an early
return on the key being absent), never route through it with `F = 1`.
"""
function rcs_aspect(rcs_broadside_m2::Real, fineness::Real, aspect_rad::Real)
    rcs_broadside_m2 > 0 || throw(DomainError(rcs_broadside_m2, "broadside RCS must be > 0"))
    fineness > 0 || throw(DomainError(fineness, "fineness ratio must be > 0"))
    s, c = sincos(aspect_rad)
    d = s * s + fineness * fineness * c * c
    return rcs_broadside_m2 / (d * d)
end

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

# --- jamming: noise jamming + the burn-through crossover (HANDOFF §10, slice 4) ---
#
# Pure phenomenology again (no geometry/entities — the jammer subsystem feeds range
# and angle in). A noise jammer raises the radar's interference floor from N to N+J;
# the detector then sees SNR_eff = (S/N)/(1 + JNR) (applied in radar.jl, NOT here).
# The headline asymmetry: the target echo is TWO-WAY (R⁻⁴), the jammer's energy reaches
# the radar ONCE (R_j⁻²) — so as the engagement closes the signal grows faster, and at
# the burn-through range it overtakes the jammer. Three named approximations live here
# (HANDOFF §1): one-way FREE-SPACE jammer path (no multipath on the J path — deferred),
# barrage `overlap = min(1,B_r/B_j)`, and the two-level antenna receive pattern.

"""
    jam_noise_ratio(rp, pj_w, gj_db, bj_hz, R_j; gr_db = rp.gain_db) -> Float64  (linear)

Jammer-to-noise ratio JNR = J/N at the radar from a noise jammer, normalized to the
**same** thermal denominator (k·T0·B·F·L) as [`snr_freespace`](@ref):

    JNR = Pj · Gj · Gr · λ² · overlap / ( (4π)² · R_j² · k·T0·B·F·L )

A **one-way (beacon) link budget**: the jammer's energy reaches the radar once, so the
spreading is `R_j⁻²` (vs the echo's two-way `R⁻⁴`) and the geometric factor is `(4π)²`
(vs the radar eq's `(4π)³`). Only the **receive** gain enters (one `Gr`, not the
monostatic `G²`) — the jammer provides its own transmit gain `Gj`. That `R_j⁻²` vs `R⁻⁴`
asymmetry is the whole burn-through lesson: doubling jammer range costs it 6 dB, the
echo 12 dB.

  • `pj_w`   jammer transmit power, W
  • `gj_db`  jammer antenna gain toward the radar, dB (one-way)
  • `bj_hz`  jammer noise bandwidth, Hz
  • `R_j`    jammer → radar range, m
  • `gr_db`  radar RECEIVE gain toward the jammer, dB (mainlobe `rp.gain_db` for a
             self-screen jammer; a sidelobe floor for standoff — see [`antenna_gain`](@ref)).

`overlap = min(1, B_r/B_j)` is the **barrage-dilution** approximation: a wideband jammer
spreads `Pj` over `B_j`, but the matched filter only collects the `B_r/B_j` fraction in
its passband (≈1 for a spot jammer matched to `B_r`; ≪1 for broadband barrage).

Named approximations (HANDOFF §1): one-way **free-space** jammer path (no multipath lobing
on the J path — deferred), barrage `overlap`, benign common-mode `F`/`L` (strictly `F`
should not amplify *external* jamming, but `F·L` cancels in `J/S = JNR/SNR`, so the
burn-through crossover is invariant to it).
"""
function jam_noise_ratio(rp::RadarParams, pj_w::Real, gj_db::Real, bj_hz::Real, R_j::Real;
                         gr_db::Real = rp.gain_db)
    R_j  > 0 || throw(DomainError(R_j, "jammer range must be > 0"))
    bj_hz > 0 || throw(DomainError(bj_hz, "jammer bandwidth must be > 0"))
    Gj = db2lin(gj_db)
    Gr = db2lin(gr_db)
    F  = db2lin(rp.noise_fig_db)
    L  = db2lin(rp.losses_db)
    λ  = wavelength(rp.freq_hz)
    overlap = min(1.0, rp.bandwidth_hz / bj_hz)
    num = pj_w * Gj * Gr * λ^2 * overlap
    den = (4π)^2 * R_j^2 * K_BOLTZMANN * T0_REF * rp.bandwidth_hz * F * L
    return num / den
end

"""
    antenna_gain(rp, θ_rad; beamwidth_rad, sidelobe_db) -> Float64  (dB)

Two-level radar receive-gain pattern (NAMED approximation, HANDOFF §1): the gain toward an
emitter at angle `θ_rad` off boresight is the full **mainlobe** `rp.gain_db` within the
half-beamwidth (`|θ| ≤ beamwidth/2`), else a flat **sidelobe floor** `rp.gain_db −
sidelobe_db`. Returns dB so it feeds [`jam_noise_ratio`](@ref)'s `gr_db` directly.

This is the standoff-vs-self-screen enabler: a self-screening jammer sits at `θ ≈ 0`
(mainlobe `Gr = G`, which cancels against the echo in `J/S`), while a standoff jammer sits
off-axis in a sidelobe (much smaller `Gr`) — physically *why* standoff jamming is weaker,
and exactly what sidelobe-blanking EP attacks. Real patterns roll off as a sinc/Taylor
taper; the two-level step captures only the in-beam-vs-sidelobe distinction (all EP needs).
The hard step at `θ = beamwidth/2` is exact and deliberate.
"""
antenna_gain(rp::RadarParams, θ_rad::Real; beamwidth_rad::Real, sidelobe_db::Real) =
    abs(θ_rad) ≤ beamwidth_rad / 2 ? rp.gain_db : rp.gain_db - sidelobe_db

"""
    burnthrough_range(rp, rcs_m2, pj_w, gj_db, bj_hz; gr_db = rp.gain_db, js_margin = 1.0) -> Float64  (m)

Self-screening **burn-through range**: the range at which a target's echo overtakes a
co-located (self-screening) noise jammer, so that `J/S = js_margin` (a **linear** ratio —
J over S, not dB, not S/J) at the returned range. In self-screening the jammer rides the
target, so both are at the same range `R`:

    S/N = K_s / R⁴   (two-way echo),    K_s = SNR·R⁴ = snr_freespace(R = 1)
    JNR = K_j / R²   (one-way jammer),  K_j = JNR·R² = jam_noise_ratio(R_j = 1)
    J/S = (K_j/K_s)·R²   ⇒   R_bt = √( js_margin · K_s / K_j )

Inside `R_bt` the signal dominates (`J/S < js_margin` → burn-through, the target
re-detects); outside, the jammer masks it. `js_margin < 1` demands the signal win by a
margin (a "usable Pd" burn-through, deeper than the bare `S = J` crossover); default `1.0`
is exactly `S = J`.

`K_s`/`K_j` are read from the actual [`snr_freespace`](@ref) / [`jam_noise_ratio`](@ref) at
unit range — NOT a re-derived constant — so any slip in either link budget moves `R_bt` in
lockstep (the project's oracle-test style).
"""
function burnthrough_range(rp::RadarParams, rcs_m2::Real, pj_w::Real, gj_db::Real, bj_hz::Real;
                           gr_db::Real = rp.gain_db, js_margin::Real = 1.0)
    js_margin > 0 || throw(DomainError(js_margin, "J/S margin must be > 0"))
    K_s = snr_freespace(rp, rcs_m2, 1.0)                               # SNR·R⁴ at R = 1
    K_j = jam_noise_ratio(rp, pj_w, gj_db, bj_hz, 1.0; gr_db = gr_db)  # JNR·R² at R_j = 1
    return sqrt(js_margin * K_s / K_j)
end
