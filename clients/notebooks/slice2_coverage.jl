### A Pluto.jl notebook ###
# v1.0.1

using Markdown
using InteractiveUtils

# ╔═╡ b0000000-0000-4000-8000-000000000002
begin
    # Thin client, but it reuses the CORE's tested artifact reader (`load_coverage`)
    # rather than re-deriving the dim/plane order. Activate the core project in a
    # throwaway env (so `EWSim` is the same tested code the suite runs) and add Plots
    # for the view. First run downloads Plots — give it a minute.
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.develop(path = joinpath(@__DIR__, "..", "..", "core"))
    Pkg.add("Plots")
    using EWSim, Plots
end

# ╔═╡ b0000000-0000-4000-8000-000000000001
md"""
# Slice 2 — coverage diagram: free-space vs two-ray

The single-pulse SNR a monostatic radar sees over a **ground-range × altitude** grid,
computed two ways — the two rungs of the `propagation` fidelity knob:

- **free_space** — no ground at all: smooth R⁻⁴ falloff, infinite line of sight.
- **two_ray** — a flat reflecting plane *and* the 4/3-Earth horizon. The
  ground-reflected ray interferes with the direct ray (`SNR = SNR_fs · F⁴`,
  $F⁴ = 16\\sin^4(Δφ/2)$, $Δφ = 4πh_r h_t/(λR_g)$), so coverage breaks into a fan of
  **interference lobes** (peaks +12 dB) and **nulls** (→ 0); and beyond the radar
  horizon the target is **masked** (no LOS).

*Dialing the knob and watching the lobes + horizon appear is the lesson* (HANDOFF §1,
§10) — the same toggle the Godot sandbox exposes as a button, here laid out over all
of range × altitude at once. The two-ray plane is exactly what the live radar computes
(the grid is pinned cell-for-cell against the sandbox's `_target_snr` in
`test_batch.jl`), so this diagram *is* the sandbox's coverage, drawn whole.

The data is `shared/coverage_radar1.bin` — a flat `(n_range, n_alt, 2)` `Float64`
array written by the core. Unlike the tiny slice-1 ROC artifact, this ~3 MB sweep is
**not** committed (`.gitignore` stages only the ROC showcase), so on a fresh clone you
must **generate it first** — and regenerate after editing the scenario or grid window:

```
pwsh tools/julia.ps1 --project=core tools/run_coverage.jl
```

then re-run the load cell below (the reader uses `read!`, not a live `mmap`, so the
file is never locked — regenerating while this notebook is open is safe).
"""

# ╔═╡ b0000000-0000-4000-8000-000000000003
artifact_path = normpath(joinpath(@__DIR__, "..", "..", "shared", "coverage_radar1.bin"))

# ╔═╡ b0000000-0000-4000-8000-000000000004
cov = load_coverage(artifact_path)   # (; free_space_db, two_ray_db, range_grid, alt_grid, rcs_m2, h_r, refl)

# ╔═╡ b0000000-0000-4000-8000-000000000005
md"""
Loaded a **$(length(cov.range_grid)) × $(length(cov.alt_grid))** grid —
RCS $(cov.rcs_m2) m², radar mast $(cov.h_r) m, reflection ρ = $(cov.refl). Ground range
$(round(first(cov.range_grid)/1e3; digits=1)) … $(round(last(cov.range_grid)/1e3; digits=1)) km,
altitude $(round(first(cov.alt_grid); digits=0)) … $(round(last(cov.alt_grid); digits=0)) m.
At sea level the 4/3-Earth horizon sits at
**$(round(horizon_range(cov.h_r, 0.0)/1e3; digits=1)) km** (it rises with target altitude).
"""

# ╔═╡ b0000000-0000-4000-8000-000000000006
begin
    xs = cov.range_grid ./ 1e3        # km on screen
    ys = cov.alt_grid                 # m

    # Heatmap z must be (n_y, n_x) = (n_alt, n_range); our planes are (n_range, n_alt).
    clim = (5, 45)                    # dB; clamps near-field saturation + floors nulls/mask to the dark end

    # Horizon boundary altitude(range): the ground range equals horizon_range(h_r, h_t)
    # at h_t = (R_g/coeff − √h_r)², where coeff = √(2·k·R_e). Recover coeff from the
    # exported helper itself (horizon_range(0,1) = coeff) — no internal constants needed.
    coeff = horizon_range(0.0, 1.0)
    hor_alt(rg) = (s = rg / coeff - sqrt(cov.h_r); s > 0 ? s^2 : 0.0)
    hxs = collect(range(coeff * sqrt(cov.h_r), maximum(cov.range_grid); length = 200))

    p_fs = heatmap(xs, ys, permutedims(cov.free_space_db);
                   clims = clim, c = :inferno, colorbar_title = "SNR (dB)",
                   title = "free_space — smooth R⁻⁴, infinite LOS",
                   ylabel = "altitude (m)")
    p_tr = heatmap(xs, ys, permutedims(cov.two_ray_db);
                   clims = clim, c = :inferno, colorbar_title = "SNR (dB)",
                   title = "two_ray — interference lobes + 4/3-Earth horizon",
                   xlabel = "ground range (km)", ylabel = "altitude (m)")
    plot!(p_tr, hxs ./ 1e3, hor_alt.(hxs);
          lc = :cyan, ls = :dash, lw = 1.5, label = "radar horizon")

    plot(p_fs, p_tr; layout = (2, 1), size = (820, 660), legend = :topright)
end

# ╔═╡ b0000000-0000-4000-8000-000000000007
md"""
**What to look for.** The top panel (free_space) is featureless — SNR just falls
smoothly with range. The bottom panel (two_ray) breaks into the **lobe fan**: bright
ridges (constructive interference, up to +12 dB over free space) separated by **nulls**
(destructive, → the floor) along lines of constant elevation angle ($h_t/R_g$ fixes
$Δφ$). The dark wedge in the lower-right is the **horizon mask** — below the cyan curve
the target's ground range exceeds the 4/3-Earth horizon, so there is no line of sight at
all. A target skimming in at low altitude (the showcase scenario's 100 m fly-by) climbs
the SNR ladder rung by rung as it crosses null → lobe → null, and only *appears* once it
clears the horizon curve.
"""

# ╔═╡ b0000000-0000-4000-8000-000000000008
begin
    # The pure multipath factor, isolated: two_ray − free_space ≈ 10·log₁₀F⁴, the lobe
    # pattern with the R⁻⁴ falloff divided out. +12 dB ridges, deep nulls, and the
    # horizon as a sharp cliff (masked cells floor, so the difference dives there).
    diff_db = cov.two_ray_db .- cov.free_space_db
    heatmap(xs, ys, permutedims(diff_db);
            clims = (-20, 12), c = :balance, colorbar_title = "F⁴ (dB)",
            title = "two_ray − free_space  =  multipath factor F⁴ (dB)",
            xlabel = "ground range (km)", ylabel = "altitude (m)", size = (820, 340))
end

# ╔═╡ Cell order:
# ╟─b0000000-0000-4000-8000-000000000001
# ╠═b0000000-0000-4000-8000-000000000002
# ╠═b0000000-0000-4000-8000-000000000003
# ╠═b0000000-0000-4000-8000-000000000004
# ╟─b0000000-0000-4000-8000-000000000005
# ╠═b0000000-0000-4000-8000-000000000006
# ╟─b0000000-0000-4000-8000-000000000007
# ╠═b0000000-0000-4000-8000-000000000008
