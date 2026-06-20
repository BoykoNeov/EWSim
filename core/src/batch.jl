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

"""
    run_batch(scn; kind=:roc, target=nothing, pfa_grid, snr_db_start, snr_db_stop,
              snr_db_count, trials, seed, outdir, name) -> Dict   (artifact descriptor)

Run an offline sweep for scenario `scn` and write its artifact. For `kind=:roc`:
sweep `pfa_grid` × `range(snr_db_start, snr_db_stop; length=snr_db_count)`, compute
analytic and MC Pd (Swerling case taken from the named radar's `comp`), write
`<outdir>/<name>.bin` + `<name>.meta.json`, and return the HANDOFF §5 descriptor.

The returned `Dict` is exactly what gets written to the sidecar and is the same shape
the server will later put on the socket (§5) — one descriptor, three uses. It carries
the §5 fields (`type/name/path/shape/dtype/axes`) plus the grid values, which a client
needs to label the axes (JSON clients ignore the extra keys).

`target` defaults to the scenario's sole radar. `rcs_m2`/`target`-as-payload from the
§5 command are accepted for wire compatibility but don't enter the math — the ROC is a
function of SNR directly (§8), so the sweep is over SNR, not range.

NB for step-7's server.jl: these kwargs (`snr_db_start`/`snr_db_stop`) are the internal
names; the §5 wire `params` spell them `snr_db_grid_start`/`snr_db_grid_stop`. The
JSON→kwargs adapter must MAP them, not drop them, or the grid bounds default silently.
"""
function run_batch(scn::Scenario;
                   kind::Symbol = :roc,
                   target = nothing,
                   rcs_m2 = nothing,                 # §5 command compat; unused (sweep is over SNR)
                   pfa_grid = [1e-8, 1e-6, 1e-4],
                   snr_db_start::Real = 0.0,
                   snr_db_stop::Real  = 20.0,
                   snr_db_count::Integer = 64,
                   trials::Integer = 100_000,
                   seed::Integer = scn.world.seed,
                   outdir::AbstractString = _default_shared(),
                   name = nothing)
    kind === :roc || error("run_batch: kind=:$kind not implemented (slice 1 carries :roc)")
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
