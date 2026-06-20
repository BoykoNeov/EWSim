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
