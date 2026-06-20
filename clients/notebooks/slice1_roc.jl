### A Pluto.jl notebook ###
# v1.0.1

using Markdown
using InteractiveUtils

# ╔═╡ a0000000-0000-4000-8000-000000000002
begin
    # Thin client, but it reuses the CORE's tested artifact reader rather than
    # re-deriving the dim/plane order. We activate the core project (so `EWSim` and its
    # `load_roc` are the same tested code the suite runs) in a throwaway env, and add
    # Plots there for the view. First run downloads Plots — give it a minute.
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.develop(path = joinpath(@__DIR__, "..", "..", "core"))
    Pkg.add("Plots")
    using EWSim, Plots
end

# ╔═╡ a0000000-0000-4000-8000-000000000001
md"""
# Slice 1 — ROC: analytic vs Monte-Carlo convergence

The radar detector's probability of detection $P_d$ as a function of single-pulse
SNR, computed **two ways** for each false-alarm rate $P_{fa}$:

- **analytic** — the closed form in `detection.jl` (Swerling 0/1),
- **Monte-Carlo** — draw complex-Gaussian noise (+ target fluctuation), threshold,
  count hits.

They should lie on top of each other. *That agreement is the first lesson and the
first regression at once* (HANDOFF §8) — the closed form is the truth, the simulation
is the honest realization the live radar actually runs, and seeing them converge is
how you trust both.

The data is `shared/roc_radar1.bin` — a flat `(n_pfa, n_snr, 2)` `Float64` array
written by the core. **Regenerate it** with

```
pwsh tools/julia.ps1 --project=core tools/run_batch.jl
```

then re-run the load cell below (the reader uses `read!`, not a live `mmap`, so the
file is never locked — regenerating while this notebook is open is safe).
"""

# ╔═╡ a0000000-0000-4000-8000-000000000003
artifact_path = normpath(joinpath(@__DIR__, "..", "..", "shared", "roc_radar1.bin"))

# ╔═╡ a0000000-0000-4000-8000-000000000004
roc = load_roc(artifact_path)   # (; pd_analytic, pd_mc, pfa_grid, snr_db_grid, swerling, trials)

# ╔═╡ a0000000-0000-4000-8000-000000000005
md"""
Loaded a **$(length(roc.pfa_grid)) × $(length(roc.snr_db_grid))** grid —
Swerling $(roc.swerling), $(roc.trials) Monte-Carlo trials per cell. SNR sweeps
$(round(first(roc.snr_db_grid); digits=1)) … $(round(last(roc.snr_db_grid); digits=1)) dB.
"""

# ╔═╡ a0000000-0000-4000-8000-000000000006
begin
    plt = plot(; xlabel = "single-pulse SNR (dB)", ylabel = "Pd",
               title = "ROC convergence — analytic vs Monte-Carlo " *
                       "(Swerling $(roc.swerling), $(roc.trials) trials)",
               legend = :topleft, ylims = (0, 1), size = (780, 500))
    for (i, pfa) in enumerate(roc.pfa_grid)
        plot!(plt, roc.snr_db_grid, roc.pd_analytic[i, :];
              label = "analytic  Pfa=$(pfa)", lw = 2, color = i)
        scatter!(plt, roc.snr_db_grid, roc.pd_mc[i, :];
                 label = "MC  Pfa=$(pfa)", ms = 3, color = i, msw = 0, alpha = 0.65)
    end
    plt
end

# ╔═╡ Cell order:
# ╟─a0000000-0000-4000-8000-000000000001
# ╠═a0000000-0000-4000-8000-000000000002
# ╠═a0000000-0000-4000-8000-000000000003
# ╠═a0000000-0000-4000-8000-000000000004
# ╟─a0000000-0000-4000-8000-000000000005
# ╠═a0000000-0000-4000-8000-000000000006
