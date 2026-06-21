# batch.jl — run_batch: offline parameter sweeps → shared/*.bin (HANDOFF §5, §8, step 6).
#
# The slice-1 sweep is the ROC: Pd(snr, pfa, swerling) computed two ways across a
# Pfa × SNR grid — analytic (closed form) and Monte-Carlo (draw/threshold/count) —
# written as a flat Float64 array the Pluto notebook reads back and plots. Their
# agreement is gate 3 ("analytic ≈ MC convergence"): the first lesson and the first
# regression at once.
#
# Determinism stance (HANDOFF §1, §12). The live "truth"/replay path is bit-exact on
# CPU; the *batch* MC is deliberately the distribution path — its job is convergence,
# not bit-equality, which is what later lets it move to threads/GPU (parallel
# reductions aren't bit-reproducible). So nothing here asserts artifact bytes. Two
# rules keep that honest:
#   • the batch owns its OWN seeded stream and never draws from `w.rng` — a sweep must
#     not desync the live trace it shares a World with;
#   • the cell loop is embarrassingly parallel (each (pfa,snr) cell is independent and
#     writes its own slot). That loop is the single seam where Threads/`CUDA.jl` drop
#     in later, behind this same function, without touching the artifact contract.
# Slice 1 runs it single-threaded (there is no server loop to keep un-stalled yet —
# HANDOFF defers server.jl to step 7), so the sweep is in fact reproducible too.

using JSON3

# --- the ROC compute core (pure: no IO, fully testable) --------------------------

"""
    roc_grid(pfa_grid, snr_db_grid, swerling, trials, rng) -> (pd_analytic, pd_mc)

Sweep Pd over the Pfa × SNR grid two ways and return two `(n_pfa, n_snr)` matrices:
closed-form [`pd_analytic`](@ref) and Monte-Carlo [`pd_montecarlo`](@ref). The MC
sweep draws sequentially from the single `rng` in a fixed cell order, so the estimate
is reproducible from a seed. This loop is the parallel seam (see file header).
"""
function roc_grid(pfa_grid::AbstractVector, snr_db_grid::AbstractVector,
                  swerling::Integer, trials::Integer, rng::AbstractRNG)
    np, ns = length(pfa_grid), length(snr_db_grid)
    pa = Matrix{Float64}(undef, np, ns)
    pm = Matrix{Float64}(undef, np, ns)
    for j in 1:ns                                   # SNR column ───┐ fixed order pins
        snr = db2lin(snr_db_grid[j])                #               │ the RNG draw
        for i in 1:np                               # Pfa row ──────┘ sequence
            pfa = pfa_grid[i]
            pa[i, j] = pd_analytic(snr, pfa; swerling = swerling)
            pm[i, j] = pd_montecarlo(snr, pfa, rng; swerling = swerling, trials = trials)
        end
    end
    return pa, pm
end

# --- the coverage compute core (slice 2 stretch; pure, fully testable) -----------
#
# The slice-2 lesson made offline: SNR over a range×altitude grid, computed two ways —
# free_space (smooth R⁻⁴) and two_ray (the same R⁻⁴ link budget modulated by the
# flat-earth interference lobes F⁴ and clipped by the 4/3-Earth horizon). The two
# planes are the "dial the propagation knob, watch the lobes + horizon appear" contrast
# (the ROC's [analytic, mc] analog). Deterministic — no RNG, so the regression is a
# closed-form recompute (test_batch pins it against the LIVE `_target_snr`, not a hand
# recompute, so the diagram provably matches what the sandbox renders).

"""
    coverage_grid(rp, rcs_m2, range_grid, alt_grid, h_r; refl=-1.0) -> (fs_db, tr_db)

Sweep single-pulse SNR (in **floored dB**) over the ground-range × altitude grid two
ways and return two `(n_range, n_alt)` matrices: `fs_db` (free-space) and `tr_db`
(two-ray, with the 4/3-Earth horizon mask). The radar sits at ground range 0, height
`h_r`; a cell `(R_g, h_t)` has slant range `√(R_g² + (h_t−h_r)²)`, so the link budget
runs on **slant** while the multipath phase + horizon run on **ground** `R_g` — the
same slant/ground decomposition as the live `_target_snr` (radar.jl), re-derived here
for the clean rectangular grid (R_g > 0, h_t ≥ 0, so the live fly-by guards don't fire).

Both planes go through [`_snr_db_wire`](@ref): a two-ray null (F⁴=0) or a below-horizon
mask drives SNR→0 and `lin2db(0) = -Inf`, which would poison the artifact exactly as it
would the wire (the slice-2 watch-item). Flooring keeps the `.bin` free of Inf/NaN. A
masked cell and a deep null both read `_SNR_DB_FLOOR` — indistinguishable by value, which
is fine for a clamped-colorscale heatmap.
"""
function coverage_grid(rp::RadarParams, rcs_m2::Real,
                       range_grid::AbstractVector, alt_grid::AbstractVector,
                       h_r::Real; refl::Real = -1.0)
    nr, na = length(range_grid), length(alt_grid)
    fs = Matrix{Float64}(undef, nr, na)
    tr = Matrix{Float64}(undef, nr, na)
    for j in 1:na                                       # altitude column ──┐ fixed order
        h_t   = Float64(alt_grid[j])                    #                   │ (no RNG, but
        d_hor = horizon_range(h_r, h_t)                 #                   │ keeps the
        for i in 1:nr                                   # range row ────────┘ loop tidy)
            R_g   = Float64(range_grid[i])
            slant = hypot(R_g, h_t - h_r)               # 3-D slant range (== _range)
            fs[i, j] = _snr_db_wire(snr_freespace(rp, rcs_m2, slant))
            # two_ray: re-derive radar.jl's below-horizon POLICY (ground beyond the
            # 4/3-Earth horizon → masked to the floor); above it, the lobed SNR.
            tr[i, j] = R_g ≤ d_hor ?
                _snr_db_wire(snr_two_ray(rp, rcs_m2, slant;
                                         h_r = h_r, h_t = h_t, ground_m = R_g, refl = refl)) :
                _SNR_DB_FLOOR
        end
    end
    return fs, tr
end

# --- artifact IO: a flat (n_pfa, n_snr, 2) Float64 array + a self-describing sidecar

# The `.bin` is the raw column-major (Julia/Fortran) bytes of an Array{Float64,3};
# the `.meta.json` next to it is the HANDOFF §5 artifact descriptor (the headless twin
# of the socket message), so the notebook reconstructs dims + axes without hard-coding
# them. `load_roc` is the canonical reader — the notebook calls it, and test_batch
# round-trips through it, so the bytes→array reconstruction is a tested path.
_meta_of(binpath::AbstractString) = first(splitext(binpath)) * ".meta.json"

"""
    load_roc(binpath) -> (; pd_analytic, pd_mc, pfa_grid, snr_db_grid, swerling, trials)

Read a ROC artifact written by [`run_batch`](@ref): mmap-free `read!` of the flat
`.bin` into an `(n_pfa, n_snr, 2)` array (dims taken from the sibling `.meta.json`),
split into the analytic and MC planes. The dim order and plane order here are the
on-disk contract — pinned by `test_batch.jl` so a transpose/plane-swap can't slip
through into the notebook's plot.
"""
function load_roc(binpath::AbstractString)
    meta = JSON3.read(read(_meta_of(binpath), String))
    shp  = Int.(meta.shape)                          # [n_pfa, n_snr, 2]
    A = Array{Float64,3}(undef, shp[1], shp[2], shp[3])
    open(binpath, "r") do io
        read!(io, A)                                 # plain read (no live mmap → no Windows file lock)
    end
    return (pd_analytic = A[:, :, 1], pd_mc = A[:, :, 2],
            pfa_grid    = Float64.(meta.pfa_grid),
            snr_db_grid = Float64.(meta.snr_db_grid),
            swerling    = Int(meta.swerling),
            trials      = Int(meta.trials))
end

"""
    load_coverage(binpath) -> (; free_space_db, two_ray_db, range_grid, alt_grid,
                                 rcs_m2, h_r, refl)

Read a coverage artifact written by [`run_batch`](@ref)`(; kind=:coverage)`: `read!`
the flat `.bin` into an `(n_range, n_alt, 2)` array (dims from the sibling
`.meta.json`), split into the free-space and two-ray SNR-dB planes. The dim order
(range, altitude) and plane order (free_space, two_ray) are the on-disk contract,
pinned by `test_batch.jl` so a transpose/plane-swap can't slip into the notebook's
heatmap. The reader is `read!` (not a live mmap) so regenerating while the notebook
is open never locks the file (same as [`load_roc`](@ref)).
"""
function load_coverage(binpath::AbstractString)
    meta = JSON3.read(read(_meta_of(binpath), String))
    shp  = Int.(meta.shape)                          # [n_range, n_alt, 2]
    A = Array{Float64,3}(undef, shp[1], shp[2], shp[3])
    open(binpath, "r") do io
        read!(io, A)
    end
    return (free_space_db = A[:, :, 1], two_ray_db = A[:, :, 2],
            range_grid = Float64.(meta.range_grid),
            alt_grid   = Float64.(meta.alt_grid),
            rcs_m2     = Float64(meta.rcs_m2),
            h_r        = Float64(meta.h_r),
            refl       = Float64(meta.refl))
end

# `shared/` at the repo root (core/src → ../.. → repo). Overridable so tests write to
# a tempdir and the headless tool can target elsewhere; the core doesn't hard-depend
# on the repo layout beyond this default.
_default_shared() = normpath(joinpath(@__DIR__, "..", "..", "shared"))

function _resolve_radar(scn::Scenario, target)
    if target === nothing
        radars = sort!(Symbol[id for (id, e) in scn.world.entities if e.kind === :radar])
        length(radars) == 1 ||
            error("run_batch: pass `target=` to pick a radar (found $(length(radars)))")
        return radars[1]
    end
    sym = Symbol(target)
    haskey(scn.world.entities, sym) || error("run_batch: target '$sym' is not an entity")
    scn.world.entities[sym].kind === :radar || error("run_batch: target '$sym' is not a radar")
    return sym
end

# Coverage needs ONE target's RCS to set the grid's link budget. Pick the sole `:target`
# entity, or error if ambiguous — the caller then passes `rcs_m2=` explicitly (mirrors
# `_resolve_radar`'s contract). Only consulted when `rcs_m2` is not given.
function _resolve_target_rcs(scn::Scenario)
    targets = sort!(Symbol[id for (id, e) in scn.world.entities if e.kind === :target])
    length(targets) == 1 ||
        error("run_batch coverage: found $(length(targets)) targets — pass `rcs_m2=` explicitly")
    return Float64(scn.world.entities[targets[1]].comp[:rcs_m2])
end

"""
    run_batch(scn; kind=:roc, target=nothing, pfa_grid, snr_db_start, snr_db_stop,
              snr_db_count, trials, seed, outdir, name) -> Dict   (artifact descriptor)
    run_batch(scn; kind=:coverage, target=nothing, rcs_m2=nothing, range_start,
              range_stop, range_count, alt_start, alt_stop, alt_count, refl,
              outdir, name) -> Dict

Run an offline sweep for scenario `scn` and write its artifact. For `kind=:roc`:
sweep `pfa_grid` × `range(snr_db_start, snr_db_stop; length=snr_db_count)`, compute
analytic and MC Pd (Swerling case taken from the named radar's `comp`), write
`<outdir>/<name>.bin` + `<name>.meta.json`, and return the HANDOFF §5 descriptor.

For `kind=:coverage` (slice-2 stretch): sweep SNR (floored dB) over a
`range_start…range_stop` × `alt_start…alt_stop` ground-range × altitude grid, two
ways — free_space and two_ray (with the 4/3-Earth horizon mask) — writing an
`(n_range, n_alt, 2)` array ([`coverage_grid`](@ref)). The radar chain + height come
from the named radar; `rcs_m2` defaults to the scenario's sole target's RCS (pass it
explicitly to disambiguate a multi-target scenario).

The returned `Dict` is exactly what gets written to the sidecar and is the same shape
the server will later put on the socket (§5) — one descriptor, three uses. It carries
the §5 fields (`type/name/path/shape/dtype/axes`) plus the grid values, which a client
needs to label the axes (JSON clients ignore the extra keys).

`target` defaults to the scenario's sole radar. For ROC, `rcs_m2`/`target`-as-payload
from the §5 command are accepted for wire compatibility but don't enter the math — the
ROC is a function of SNR directly (§8), so the sweep is over SNR, not range; for
coverage `rcs_m2` finally does enter (it sets the grid's link budget).

NB for step-7's server.jl: these kwargs (`snr_db_start`/`snr_db_stop`) are the internal
names; the §5 wire `params` spell them `snr_db_grid_start`/`snr_db_grid_stop`. The
JSON→kwargs adapter must MAP them, not drop them, or the grid bounds default silently.
"""
function run_batch(scn::Scenario;
                   kind::Symbol = :roc,
                   target = nothing,
                   rcs_m2 = nothing,                 # ROC: §5 compat, unused. Coverage: the grid RCS.
                   pfa_grid = [1e-8, 1e-6, 1e-4],
                   snr_db_start::Real = 0.0,
                   snr_db_stop::Real  = 20.0,
                   snr_db_count::Integer = 64,
                   trials::Integer = 100_000,
                   # coverage grid (kind=:coverage); ignored by :roc. Defaults frame the
                   # LOW-elevation band where the lobe fan is teachable and the horizon
                   # bites: a 30 m X-band mast packs ~940 lobes over the hemisphere, so
                   # high elevation angles (short range × high altitude) alias into moiré.
                   # 10–80 km × 0–600 m keeps ~2–4 grid cells per lobe (see run_coverage.jl).
                   range_start::Real = 10_000.0,
                   range_stop::Real  = 80_000.0,
                   range_count::Integer = 400,
                   alt_start::Real = 0.0,
                   alt_stop::Real  = 600.0,
                   alt_count::Integer = 480,
                   refl::Real = -1.0,
                   seed::Integer = scn.world.seed,
                   outdir::AbstractString = _default_shared(),
                   name = nothing)
    if kind === :coverage
        return _run_coverage(scn; target = target, rcs_m2 = rcs_m2,
                             range_start = range_start, range_stop = range_stop,
                             range_count = range_count, alt_start = alt_start,
                             alt_stop = alt_stop, alt_count = alt_count, refl = refl,
                             outdir = outdir, name = name)
    end
    kind === :roc || error("run_batch: kind=:$kind not implemented (:roc | :coverage)")
    rid = _resolve_radar(scn, target)
    swerling = Int(scn.world.entities[rid].comp[:swerling])
    nm = name === nothing ? "roc_$(rid)" : String(name)

    pfa_vec    = Float64.(collect(pfa_grid))
    snr_db_vec = collect(range(Float64(snr_db_start), Float64(snr_db_stop);
                               length = Int(snr_db_count)))

    # OWN seeded stream — never `scn.world.rng` (a sweep must not desync the live trace).
    rng = Xoshiro(UInt64(seed))
    pa, pm = roc_grid(pfa_vec, snr_db_vec, swerling, trials, rng)

    np, ns = length(pfa_vec), length(snr_db_vec)
    A = Array{Float64,3}(undef, np, ns, 2)
    A[:, :, 1] .= pa
    A[:, :, 2] .= pm

    mkpath(outdir)
    binpath = joinpath(outdir, "$nm.bin")
    open(binpath, "w") do io
        write(io, A)                                 # raw column-major Float64 bytes
    end

    descriptor = Dict{Symbol,Any}(
        :type        => "artifact",
        :name        => nm,
        :path        => binpath,
        :shape       => [np, ns, 2],
        :dtype       => "f64",
        :order       => "col",                        # column-major (Julia/Fortran), native-endian
        :axes        => ["pfa", "snr_db", "[pd_analytic, pd_mc]"],
        :pfa_grid    => pfa_vec,
        :snr_db_grid => snr_db_vec,
        :swerling    => swerling,
        :trials      => Int(trials),
    )
    open(_meta_of(binpath), "w") do io
        JSON3.write(io, descriptor)
    end
    return descriptor
end

# kind=:coverage body — kept out of run_batch so the ROC path above stays byte-for-byte
# the slice-1 code (those 279 tests are green by construction). The radar chain + mast
# height come from the named radar; the RCS from `rcs_m2` or the sole target. No RNG at
# all (the grid is closed-form), so `seed`/`scn.world.rng` never enter — a coverage run
# can't desync a live trace even in principle.
function _run_coverage(scn::Scenario; target, rcs_m2,
                       range_start, range_stop, range_count,
                       alt_start, alt_stop, alt_count, refl, outdir, name)
    rid   = _resolve_radar(scn, target)
    radar = scn.world.entities[rid]
    rp    = _radar_params(radar.comp)
    h_r   = Float64(radar.pos[3])
    rcs   = rcs_m2 === nothing ? _resolve_target_rcs(scn) : Float64(rcs_m2)
    nm    = name === nothing ? "coverage_$(rid)" : String(name)

    range_vec = collect(range(Float64(range_start), Float64(range_stop); length = Int(range_count)))
    alt_vec   = collect(range(Float64(alt_start),   Float64(alt_stop);   length = Int(alt_count)))
    fs, tr = coverage_grid(rp, rcs, range_vec, alt_vec, h_r; refl = Float64(refl))

    nr, na = length(range_vec), length(alt_vec)
    A = Array{Float64,3}(undef, nr, na, 2)
    A[:, :, 1] .= fs                                  # free_space SNR dB
    A[:, :, 2] .= tr                                  # two_ray SNR dB (horizon-masked)

    mkpath(outdir)
    binpath = joinpath(outdir, "$nm.bin")
    open(binpath, "w") do io
        write(io, A)                                 # raw column-major Float64 bytes
    end

    descriptor = Dict{Symbol,Any}(
        :type       => "artifact",
        :name       => nm,
        :path       => binpath,
        :shape      => [nr, na, 2],
        :dtype      => "f64",
        :order      => "col",                         # column-major (Julia/Fortran), native-endian
        :axes       => ["ground_range_m", "altitude_m", "[free_space_db, two_ray_db]"],
        :range_grid => range_vec,
        :alt_grid   => alt_vec,
        :rcs_m2     => rcs,
        :h_r        => h_r,
        :refl       => Float64(refl),
    )
    open(_meta_of(binpath), "w") do io
        JSON3.write(io, descriptor)
    end
    return descriptor
end
