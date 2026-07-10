# Slice 14 — cooperative guidance: a salvo of interceptors sharing time-to-go for simultaneous arrival (the capstone)

HANDOFF **§10 item 13** — *"Cooperative guidance — multiple interceptors sharing state. **Capstone.**"* The missile
guidance arc (slices 8–12) built the single-interceptor stack (`integrate!` + `observe!` + `decide!`); slice 13
opened the countermeasures arc. Slice 14 **closes the committed roadmap** by putting **N interceptors in one
scenario** and letting them **share state through the guidance law**: each missile's **time-to-go** `t_go` is
pooled over an ideal datalink into a team **desired impact time** `t_d`, and an **impact-time-control** term shapes
each trajectory so **all N arrive together** (a salvo). The lesson is **solo spread vs coordinated
simultaneous-arrival**: uncoordinated PN interceptors at different ranges impact at spread-out times (a defender
picks them off one at a time); the cooperative law drives the **arrival spread → 0** while every missile still
hits. Source of truth: HANDOFF §10 item 13 + §3 (the tick contract — phase-2 `build_env!` cross-subsystem field,
phase-4 `decide!`) + §9 (the shared-library reuse map) + §1 (named approximations).

## SCOPE FORK (C) IS RATIFIED (user, 2026-07-10) — guidance-law cooperation, NOT distributed estimation / WTA

Three readings of "cooperative guidance — multiple interceptors sharing state" were on the table; the user ratified
**(C) guidance-law cooperation** (shared state = time-to-go / impact-time; a cooperation term in the guidance law
reusing the slice-8–12 PN machinery). The plan is written around (C). **The other two readings are HANDOFF §11
Tier C horizons, deliberately NOT pulled forward (advisor, load-bearing):**

- **(A) distributed / measurement-fusion estimation** (N seekers fuse bearings → one shared track) is HANDOFF §11
  Tier C — *"Swarms & distributed estimation. **Past cooperative guidance:** consensus filtering, distributed
  sensing, swarm tactics."* It is named as the horizon **beyond** item 13. Its §9 cross-domain-reuse pull (same
  `gauss_newton` fixing DF N=2 / GPS N=4) is **already banked at slice 7** — re-closing it is not what item 13 asks.
- **(B) weapon–target assignment / C2** (coordinate one-to-one against a raid) is HANDOFF §11 Tier C — the
  *"Decision / C2 layer … weapon–target assignment, radar time-budget … engagement scheduling."* It needs a
  commander tier the core does not have.

So (C) is the reading that **stays inside the missile/guidance arc it is the capstone of**, is **not named
elsewhere as a separate horizon**, and is **one bounded slice** rather than the emergent-behaviour horizon §12
flags as *the* dominant scope risk. **DEFERRED, NAMED (convention 9):** consensus filtering / noisy-lossy-latent
datalink (the Tier-C "consensus filtering" thread), cooperative *estimation* (A), weapon–target assignment (B),
and — within (C) — the cooperative **approach-angle** geometry variant and any explicit **point-defense** model
(see § "the lesson" and gate-0 decision 1).

## THE SHARED STATE IS `t_go`, POOLED OVER AN IDEAL DATALINK (name the approximation)

"Multiple interceptors sharing state" is realized **literally**: each interceptor's time-to-go `t_go ≈ R/V_c` is
published to a team-level field; the consensus desired impact time is `t_d = max_j t_go_j` (the **slowest** missile
sets the pace — the only choice that is achievable by all, since a missile can *stretch* its path but cannot
*shorten* below its minimum-time trajectory). Each missile then flies **impact-time-control guidance** (PN base +
a feedback term that nulls `t_d − t_go`).

**WHEN is `t_d` computed — a gate-0 fork; FIXED-AT-LAUNCH is the robustness DEFAULT (advisor, load-bearing).**
A **per-tick** `t_d = max_j t_go_j` recompute has a KNOWN instability: as a fast missile stretches, its
`t_go = R/V_c` *RISES* (stretching cuts `V_c`), so with a hot `K_it` it can overshoot and **become the new max →
the reference missile CHATTERS → non-convergence.** The clean fix is a **one-time consensus computed ONCE at
launch** (`t_d = max_j t_go_j(0)`) — still "sharing state" (arguably cleaner), it eliminates reference-switching
entirely, and a small residual `:salvo` spread from PN curvature is fine because the headline pins the *ratio*, not
absolutes. **Slice 14 makes fixed-at-launch `t_d` the default the probe must BEAT** (gate-0 decision #2/#3); the
per-tick max is the named alternative, admitted only if the probe shows it converges without chatter under the
pinned `K_it`. Either way the coordinator is the single writer of `w.env[:salvo_t_d]`; fixed-at-launch just means
it writes the same constant every tick after t=0. **Named approximation: the datalink is IDEAL** — zero-latency, lossless,
truth-shared `t_go` (at truth fidelity every missile reads the same world, so consensus = a single deterministic
`max`). A **noisy / latent / lossy datalink + consensus filtering** is the HANDOFF §11 Tier-C horizon, DEFERRED —
naming it that way keeps slice 14 out of Tier C.

**THE DEGENERATE ANCHOR (the additivity teeth):** with **one** interceptor, `t_d = t_go` of that one missile →
the impact-time error is identically zero → the feedback term vanishes → **`:salvo` ≡ `:pn`** for a solo missile
(the exact `:apn`-on-a-CV-target ≈ `:pn` shape from slice 12). The cooperation only bites with **N ≥ 2** at
**different ranges** (differing natural `t_go`). State + test this — it is the byte-identity bridge from every
prior single-missile slice.

## THE DETERMINISM SHAPE — the RNG inflection INVERTS BACK to VACUOUS (slice-12 shape, class 4c, NOT slice-13's 4b)

The missile-arc RNG story has flip-flopped every slice — **name this beat, copy neither neighbour verbatim
(convention 4c, the copy-paste false-claim trap):**

- Slices **8/9/10** — no RNG → "draw-count invariance is VACUOUS."
- Slice **11** — the Seeker is the first `w.rng` consumer → conventions 3/11 APPLY ("1 draw/tick").
- Slice **12** — no seeker (truth-fed APN) → the inflection INVERTS BACK ("vacuous" again).
- Slice **13** — the seeker is BACK (the decoy seduces a *seeker*) → `w.rng` draws (2·N_p·N_bins) → RE-INVERTS to
  APPLIES; class **4b** (draw-topology-flip, introduce-rejected).
- Slice **14** — **cooperative guidance is TRUTH-FED PN (no seeker in the scenario — the cooperation lesson is
  isolated exactly as slice 12 isolated APN).** No `w.rng` consumer → the inflection **INVERTS BACK to VACUOUS
  again** (the slice-12 shape, one arc-item later). **Do NOT carry slice-13's "2·N_p·N_bins draws / conventions
  3/11 apply / draw-topology 4b" language — that is the false claim here** (the convention-4c trap running the
  slice-13→14 direction, exactly as slice 12→13 ran the other way).

**The fidelity CLASS is 4c — physics-changing, no RNG** (the `:integrator` / `:autopilot` shape; the `:apn` rung's
shape). A `:solo↔:salvo` toggle **CHANGES the trajectory** (moves the missile — not a dead knob) with **no RNG
stream at all**, so:

- **"Draw-count invariance" is VACUOUS** (there is no RNG to keep in lockstep) — write it that way, NOT the
  slice-13 "the sharp property to prove" language.
- **No draw-topology to flip → NO introduce-reject guard** (unlike slice-13 `:scan` / slice-3 `:cfar`). `:cooperation`
  is **live-settable** (`set_fidelity` may switch `:solo↔:salvo` at will — the `:integrator`/`:autopilot`
  precedent), because switching it moves the trajectory but touches no RNG topology.
- Additivity is via the **physics being unreachable without the mode + the coordinator**: absent the
  `SalvoCoordinator` subsystem AND with `cooperation ∈ {absent, :solo}`, the `t_d` field is never read → a
  slice-1..13 scenario is **byte-identical** (the class-4c additivity — like introducing `:apn` left slices 1–11
  identical).

The additivity claims (the byte-identity master check — slices 1–13):

1. **Introduce-safe / additivity — via the mode + the coordinator, NOT a live draw.** Absent a `SalvoCoordinator`
   entity AND with `cooperation` unset-or-`:solo`, nothing new runs: a slice-1..13 scenario is **byte-identical**
   (no RNG added anywhere — guidance.jl stays pure; the coordinator only writes an env field nobody reads under
   `:solo`). A slice-10/12 single-PN scenario replays **bit-identical** after the guidance.jl / missile.jl /
   radar.jl edits.
2. **Same-config replay is bit-identical** — deterministic and **RNG-free** on the missile path (the slice-12
   shape): the verifier pins `t` AND a per-missile `pos` sequence, both RNG-independent (NOT slice-13's
   RNG-affected pos — there is no seeker draw here; [[ewsim-missile-verifier-sampling]]).
3. **A `:solo↔:salvo` toggle CHANGES the trajectory** (the not-a-dead-knob property) — the arrival spread collapses
   and the salvo paths stretch — with **no RNG** (class 4c; the slice-12 `:pn↔:apn` shape, now over N missiles).

## The lesson (shown as numbers — the LANDING IS EMPIRICAL, the slice-12/13 discipline)

**A salvo of interceptors sharing `t_go` arrives together; uncoordinated PN arrives spread out.** The headline
metric is the **arrival spread** `Δτ = max_j τ_impact,j − min_j τ_impact,j` over the N interceptors:

- **`:solo` (no cooperation) spreads.** Each missile flies plain PN and impacts at its own natural `t_go`; missiles
  launched from different ranges/geometries hit at different times → a **large `Δτ`** (a defender engages them one
  at a time — the "why simultaneous arrival matters" framing; see gate-0 decision 1 on whether to MODEL a defender
  or let the metric self-justify).
- **`:salvo` (cooperation on) converges.** Each missile drives `t_go → t_d = max_j t_go_j`; the faster missiles
  **stretch** their paths (S-curve / lead-and-lag), the slowest flies ~straight, and **all N reach the target
  within a tight `Δτ ≈ 0`** — while every missile **still hits** (miss stays small; cooperation reshapes *timing*,
  not accuracy).

**⚠ CAUTION — do NOT pin the landing from theory (the slice-12/13 lesson VERBATIM).** Slice 12's probe found plain
PN *intercepts anyway* under a generous `a_max` (the miss lesson needed a *binding* constraint). Analogously,
whether `:salvo` collapses `Δτ` cleanly depends on the **g-limit** (a missile forced to stretch a lot may
**saturate `a_max`** and fail to delay enough — the slice-10/12 saturation lesson resurfacing), the **`t_d`
choice** (`max t_go` must be *reachable* by the missile that has to stretch furthest), and the **impact-time-error
gain** (too hot → oscillates; too cold → doesn't converge before impact). The probe MUST report `Δτ(:solo)` vs
`Δτ(:salvo)` **AND** per-missile miss for both, **AND** whether `a_max` binds during the stretch, and **pick the
headline from the data** (spread-ratio if it collapses cleanly; if the salvo missile saturates and can't delay,
either soften the geometry or, as in slice 12, make the constraint the *lesson* — "the g-limit caps how much a
salvo can compress"). **Pin the RATIO** (`Δτ(:solo)/Δτ(:salvo)`), not absolutes (the
[[ewsim-missile-verifier-sampling]] frame-sampling floor + per-missile first-CPA discipline).

**The cooperation can ALSO fail (name the failure regime — the slice-13 "gate can fail" discipline).** If the
launch geometry is nearly symmetric (all `t_go` already equal) the lesson is vacuous (`:solo` already
simultaneous); if one missile's required stretch exceeds what `a_max` allows before impact, `:salvo` can't pull it
to `t_d` (saturates); if `t_d` is authored *below* the slowest missile's minimum time, it is unreachable. The probe
pins the **range/geometry asymmetry** (so `:solo` visibly spreads) AND a **`t_d = max t_go`** that every missile
can reach without saturating — and reports the robust window (a learner's launch-range nudge can't silently erase
the lesson — the slice-12 `a_max ∈ [100,350]` window discipline).

## The truth-path / kind invariants (advisor-style guards, slice-13 precedent)

- **Interceptors are `kind === :missile`; the target is `kind === :target`; the datalink is a NEW non-physical
  `kind === :datalink`.** `_nearest_target` (radar.jl:221) filters `kind === :target`, so N missiles never target
  each other and never target the datalink node — each missile's truth target is the single common `:target`
  (verify + test). The `SalvoCoordinator` identifies the interceptor SET by `kind === :missile` (the esm/gps
  `count(kind===…)` precedent) — never by hard-coded ids.
- **The coordinator is the SOLE writer of the shared field** `w.env[:salvo_t_d]` (single-writer discipline). Each
  `Autopilot.decide!` (phase 4) only READS it. build_env! is phase 2 (after the single `empty!(w.env)`), so the
  field survives to phase 4 (the slice-4 jammer / slice-8 energy-readout telemetry-phase precedent).
- **Miss/CPA is per-missile and always vs the true `:target`** — the verifier asserts each interceptor's honest
  truth-miss AND the team `Δτ`.

## Scope — one lesson per scenario (fork (C) RATIFIED)

**N = 2 interceptors** (start minimal; the machinery generalizes to N — one lesson) `[BallisticMissile, Autopilot]`,
launched at **different ranges** (asymmetric natural `t_go`), against a **single common target** `[ConstantVelocity]`
(or stationary — gate-0 picks), plus a **`[SalvoCoordinator]` datalink node** (`kind === :datalink`, no mover,
phase-2 `build_env!` only). Held: **`guidance = :pn`, `autopilot = :ideal`, NO seeker** (truth-fed — the cooperation
lesson isolated exactly as slice 12 isolated APN; the slice-10/11/12 isolation discipline). The switchable
**fidelity is `cooperation ∈ (:solo, :salvo)`** — the NEW key; the lesson is the `:solo↔:salvo` compare on `Δτ`.
**Deferred, NAMED (convention 9):**

- **Consensus filtering / noisy-lossy-latent datalink** (the Tier-C horizon) — slice 14 shares `t_go` over an
  **ideal** (truth, zero-latency) link. Datalink degradation + distributed consensus is a later slice.
- **Cooperative approach-ANGLE geometry** (missiles converge from spread bearings to defeat aspect-dependent
  defenses / for lethality) — a *different* shared-state cooperation within (C); slice 14 ships the **impact-TIME**
  variant (the cleaner, self-justifying-by-metric one — gate-0 decision 1). Named, not built.
- **An explicit point-defense / defender model** ("why simultaneous arrival matters") — slice 14 lets the **`Δτ`
  metric self-justify** (spread → 0 is the number); a shooter that engages spread arrivals one-at-a-time is a
  later C2/red-team piece (gate-0 decision 1 — the probe confirms the metric lands without needing a defender).
- **N > 2 / heterogeneous interceptors / weapon–target assignment** (B) — the machinery paints N missiles; the
  scenario ships **2** (one lesson). WTA is Tier C.
- **Decoys / countermeasures in the salvo** (slice-13 machinery) — one lesson per scenario; the salvo flies against
  a clean target.

**One scenario** (one lesson; the button toggles `:solo↔:salvo`; the launch geometry is fixed in the scenario).
3 review gates + a gate-0 probe (mirroring slices 5–13).

## The physics / math (named approximations — HANDOFF §1)

### 1. Time-to-go + impact-time-control guidance (guidance.jl — pure, RNG-free, no LinearAlgebra)

NEW pure functions in `core/src/guidance.jl` (the §9 pure lib that already holds `pn_accel`/`pn_accel_augmented`/
`_terminal_cutoff`), tested closed-form. **The exact gain algebra is PROBE-PINNED (gate 0) — the plan fixes the
structure, the probe fixes the constants** (the slice-13 "structure in the plan, numbers in FINDINGS" discipline):

    time_to_go(range, closing_speed) -> Float64
        # first-order t_go ≈ R / V_c (V_c = −range_rate, POSITIVE closing). Named approximation: the zeroth-order
        # estimate; the PN-curvature correction t_go·(1 + λ̇²/(2(2N−1))) is a fidelity choice the probe may add if
        # the zeroth-order estimate under-delays. GUARD: V_c ≤ 0 (receding / at CPA) → the engagement is over for
        # timing purposes → return a finite sentinel (0 or the last t_go), never Inf/NaN (convention 6).

    salvo_consensus(t_go_list) -> t_d          # the shared-state reduction: t_d = maximum(t_go_list)
        # the ONLY achievable common time (a missile can stretch, not shorten). One element → itself (the solo
        # degenerate anchor → :salvo ≡ :pn). Pure reduction over the team's published t_go. (Fixed-at-launch means
        # the coordinator calls this ONCE at t=0 and republishes the constant; per-tick means it recomputes — the
        # gate-0 fork above, fixed-at-launch the default.)

    impact_time_control_accel(m_pos, m_vel, t_pos, t_vel, t_d; N, K_it) -> Vec3
        # PN base (pn_accel) + a feedback lateral term proportional to the impact-time error (t_d − t_go) that
        # LENGTHENS the path when the missile is early (t_go < t_d). The classic ITCG family (Jeon–Lee–Tahk 2006:
        # a = N·V·λ̇ + biased feedback on impact-time error). The SIGN is the trifecta trap (§1): early ⇒ stretch
        # ⇒ the bias must add curvature that INCREASES flight time — pin the sign closed-form (a missile that is
        # early flies a LONGER arc, not a shortcut). t_go from time_to_go; the feedback perpendicular to the LOS
        # (like the PN command) so it shapes the path without fighting the closing geometry.
        # TWO GUARDS (advisor): (i) EARLY-RETURN pn_accel(...) when the impact-time error is EXACTLY zero — do NOT
        # return `pn_accel + zero(Vec3)` (the −0.0+0.0→+0.0 sign-bit flip breaks the solo `===` anchor, the same
        # ±0.0 bit trap cited in the watch-items); the early return GUARANTEES `:salvo`≡`:pn` bit-identity. (ii)
        # If the pinned gain form carries a 1/t_go (or 1/(V·t_go)) factor, the feedback term blows up as t_go→0
        # INDEPENDENTLY of the PN LOS-rate→∞ — extend `_terminal_cutoff` (or a floor) to the FEEDBACK term too,
        # not just the PN base (a distinct terminal trap — see watch-items).

- **`COOPERATION_MODES = (:solo, :salvo)`** in guidance.jl (the one-list source of truth, defined **before
  radar.jl** so `LIVE_FIDELITY_MODES` can reference it — the drift-catch); `GUIDANCE_MODES`/`pn_accel`/etc.
  **UNCHANGED** (byte-identity anchor). Export the three fns + `COOPERATION_MODES`.
- **Reuse `pn_accel` UNCHANGED as the base term** (`impact_time_control_accel` calls it — the "fuses the arc"
  reuse is honest: the salvo law is PN + a shaping term, not a rewrite). `los_range`/`range_rate` (frames.jl)
  for `t_go`; `los_unit`/`los_rate` for the perpendicular feedback direction.

### 2. The `SalvoCoordinator` build_env! subsystem (missile.jl — the shared-state seam)

A NEW phase-2 `build_env!` subsystem on a `kind === :datalink` entity (no mover — it never integrates). It:

    ids   = sort(interceptor ids by kind === :missile)          # the team set (esm/gps count-by-kind precedent)
    t_gos = [time_to_go(los_range(m.pos, tgt.pos), −range_rate(m.pos−tgt.pos, m.vel−tgt.vel)) for m in ids]
    w.env[:salvo_t_d] = salvo_consensus(t_gos)                  # the shared state, single-writer

Named approximations: **ideal datalink** (reads truth `pos`/`vel` of every interceptor — zero-latency, lossless);
the target is the single common `:target` (`_nearest_target` semantics). **Byte-identity:** this subsystem exists
only in a slice-14 scenario; absent it, `w.env[:salvo_t_d]` is never written and (under `:solo`) never read.
**Determinism-phase note:** build_env! runs post-`empty!(w.env)` (phase 2), so the field is live for phase-4
`decide!` (the slice-4/8 telemetry-phase discipline). **ALTERNATIVE the probe may pick (gate-1 forward-flag):** if
the coordinator entity proves awkward, each `Autopilot.decide!` can compute the consensus itself by reading all
`:missile` truth (no coordinator entity) — deterministic and identical at truth fidelity; the coordinator is the
cleaner "shared state lives in env" reading (roadmap wording) and the single-writer discipline. Gate 0 decides.

### 3. The `Autopilot.decide!` extension (missile.jl — the `:salvo` guidance branch)

`Autopilot.decide!` (missile.jl:270) today selects the OUTER law on `:guidance` (`:pursuit`/`:pn`/`:apn`).
Slice 14 adds a **cooperation modifier** read from `:cooperation` (default `:solo` = the exact slice-10/12 truth
PN path → byte-identical):

    coop = get(w.fidelity, :cooperation, :solo)
    a_dem = if guid === :pn && coop === :salvo && haskey(w.env, :salvo_t_d)
                impact_time_control_accel(e.pos, e.vel, tgt.pos, tgt.vel, w.env[:salvo_t_d]; N=n_pn, K_it=k_it)
            elseif guid === :pn && haskey(c, :seeker_omega)     # slice-11 seeker path — UNCHANGED
                ...
            elseif guid === :pn                                  # slice-10 truth PN — UNCHANGED
                pn_accel(...)
            elseif guid === :apn                                 # slice-12 — UNCHANGED
                ...
            else                                                 # pursuit — UNCHANGED
                ...

then the EXACT slice-9/10 `_terminal_cutoff` → `clamp_accel(a_dem, a_max)` → inner PID → telemetry, PLUS new
per-missile keys (`t_go`, `t_d`, `impact_time_err`, and — on `:impact` — the recorded `τ_impact`; all SCALARS, no
Array → no `float()`-crash). **BYTE-IDENTITY (slices 1–13):** the `:salvo` branch is gated on
`coop === :salvo && haskey(w.env, :salvo_t_d)` — UNREACHABLE without both the mode AND the coordinator; every other
arm is the prior-slice arithmetic **textually unchanged** (keep the salvo fetch INSIDE its branch — the slice-12
`a_T`-fetch-inside-the-branch / `+0.0` bit trap; use the slice-10 PN spelling verbatim in the non-salvo arms) →
slices 1–13 byte-identical BY CONSTRUCTION. `K_it` (`c[:k_it]`) is a live guidance knob (clamp-at-consumer floor;
a huge value just curves harder — "a live slider can't crash a tick", but `clamp_accel`/`_finite` still bound the
command).

### 4. Recording per-missile arrival time (the metric source)

The headline `Δτ` needs each interceptor's **arrival time** `τ_j`.

**⚠ GATE-2 CORRECTION (advisor-confirmed — this section's original ground-`:impact` plan is WRONG for geometry F).**
The plan sketched stamping `τ_impact = w.t` at the `BallisticMissile` `:impact` seam (missile.jl:121). But gate-0
ratified an **AIR intercept** — a MOVING target at altitude 4500 m (to dodge the ground-target gravity-droop miss).
For an air intercept the missile reaches the target at **CPA**, COASTS PAST (r_stop=30), and the `:impact` event
(ground, `z ≤ 0`) fires only LATER on the fall — so `:impact` is the fall-to-ground time, **never** the intercept.
Wiring the `t_impact` stamp gave `:solo` τA=7.55 s (the fall) instead of the true CPA 5.04 s. **So slice 14 stamps
NO arrival time in the core.** The metric is the **first-CPA time of each missile's `los_range` stream** (already
on the wire from `Autopilot.decide!`), computed **consumer-side** by the verifier/tests with the descending-band
`first_cpa` (running-min, break only once well past the min — the slice-10..12 miss-distance discipline;
[[ewsim-missile-verifier-sampling]]). `Δτ = |CPA_A − CPA_B|`; pin the RATIO. `emit_every=16` makes CPA coarse
(±16 ms) — fine, the FINDINGS bounds (`Δτ_solo > 2.0`, `Δτ_salvo < 1.0`) are coarse-tolerant. The coordinator stays
**single-purpose** (publish `salvo_t_d`); the removed `t_impact` comp write restores `integrate!` bit-for-bit for
slices 8–13. A missile that MISSES still yields a CPA time from the same running-min (a salvo that fails to converge
is a real, reportable outcome, not a silent NaN).

**GATE-3 FORWARD-FLAG:** `slice14_verify.gd` + the Godot arrival-time readout must derive each missile's arrival as
the **first-CPA of its shipped `los_range` scalar** (a display min-tracker, NOT physics — consistent with the
Godot-pure invariant), NOT a `t_impact` key (there is none). Do not take the ground-`:impact` assumption at face
value.

### 5. Fidelity plumbing — `:cooperation` (class 4c, live-settable, no introduce-reject)

`LIVE_FIDELITY_MODES += cooperation = COOPERATION_MODES` (radar.jl, one-list-no-drift; `_validate_fidelity` picks
up the new tuple automatically). **`set_fidelity` gains NO new guard** (unlike slice-13 `:scan` / slice-3 `:cfar`):
`:cooperation` is class 4c (physics-changing, no RNG → no draw-topology to flip → introduce-safe like
`:integrator`/`:autopilot`), so `:solo↔:salvo` is **live-settable**. Class map: `:cooperation` = **4c**
(trajectory-changing, no RNG — "draw-count invariance VACUOUS", the slice-12 shape; do NOT write slice-13's "draws
2·N_p·N_bins" language). Orthogonal held keys: slice-14 scenarios pin `guidance=:pn`, `autopilot=:ideal`, no seeker
so the ONE button toggles the ONE cooperation lesson (convention 9).

## Decisions to take at gate 0 (surface to the advisor before gates 1–3)

1. **The HEADLINE — spread-ratio vs saturation contrast, AND whether a point-defense model is needed.** Report
   `Δτ(:solo)`/`Δτ(:salvo)` AND per-missile miss AND whether `a_max` binds during the stretch; pick from the data;
   pin the RATIO. Confirm the **`Δτ` metric self-justifies** (spread → 0 is the number) so **no defender model is
   required** (keep it deferred); escalate to a binding-`a_max` "the g-limit caps salvo compression" framing only
   if the clean-collapse landing doesn't materialize (the slice-12 pivot).
2. **The launch geometry + `t_d`, AND fixed-at-launch vs per-tick consensus (the advisor fork).** The two
   interceptors' ranges/headings so their natural `t_go` DIFFER enough that `:solo` visibly spreads, AND
   `t_d = max t_go` is **reachable** by the faster missile without saturating `a_max` before impact (the §
   "cooperation can fail" window). **Default `t_d` = FIXED-AT-LAUNCH** (`max_j t_go_j(0)`, no reference-chatter);
   the probe only admits the **per-tick max** if it converges without the reference missile chattering (a fast
   missile's `t_go` rises as it stretches → can steal the max). Sweep the geometry the run traverses; confirm the
   stretch stays sub-`a_max` throughout. Target stationary vs constant-velocity (pick the one that keeps the CPA
   clean — [[ewsim-missile-verifier-sampling]]).
3. **The impact-time-control gain `K_it` + the `t_go` estimator order + the terminal bound.** Hot enough to
   converge `t_go → t_d` before impact, cold enough not to oscillate (and not to feed the per-tick-max chatter, #2);
   whether the zeroth-order `t_go ≈ R/V_c` suffices or the PN-curvature correction is needed (add only if it
   under-delays). **Verify the feedback term stays BOUNDED as `t_go→0`** — if the pinned gain form has a `1/t_go`
   factor, extend the terminal cutoff/floor to it (the ITCG-specific blowup, distinct from the PN LOS-rate→∞ that
   `_terminal_cutoff` already guards). Report the robust `K_it` window (a slider nudge can't erase the lesson — the
   slice-12 discipline).
4. **The coordinator seam** — the `[SalvoCoordinator]` datalink node (shared field in `w.env`) vs each-missile-
   reads-truth (§2 alternative). Pick the single-writer env field unless the probe finds it awkward.
5. **The SIGN of the impact-time feedback is right** — an EARLY missile flies a LONGER arc (delays), a `Δτ(:salvo)
   < Δτ(:solo)` closed-loop AND a direct `impact_time_control_accel`/`time_to_go`/`salvo_consensus` recompute (a
   DIFFERENT expression) in `test_guidance.jl` (the slice-10/12 two-source sign-pin; the perpendicular-direction
   sign is the trap).
6. **The solo degenerate anchor** — ONE interceptor: `salvo_consensus([t_go]) === t_go` → impact-time error 0 →
   `:salvo` command `===` the `:pn` command (bit-exact, the additivity bridge — convention 11's bit-exact no-op).
7. **Byte-identity** — a slice-10/12 single-PN scenario replays bit-identical after the guidance.jl/missile.jl/
   radar.jl edits (RNG-free — pin `t` AND a pos sequence, the slice-12 shape); NO seeker, NO `w.rng` draw
   (the class-4c "vacuous" property — state it, don't claim slice-13 draws).
8. **Multi-interceptor plumbing works** — 2 `[BallisticMissile, Autopilot]` stacks + a `[SalvoCoordinator]` node
   in one world; both Autopilots guide independently (`a.id`-keyed), `_nearest_target` returns the common target
   for each, neither missile targets the other or the datalink node (the FIRST multi-interceptor scenario — name
   the milestone).
9. **One scenario, geometry/`t_d`/`K_it`/`a_max` values** — pinned by the probe against the live wire (convention 10).

## Review gates (cadence: staged, mirroring slices 5–13)

0. **Gate-0 probe (throwaway, `M:\claud_projects\temp\slice14_probe\`).** Reuse the REAL core physics
   (`using EWSim`: `total_accel`/`integrator_step`/`pn_accel`/`los_unit`/`los_range`/`range_rate`/`los_rate`/
   `clamp_accel`/`_terminal_cutoff`), hand-roll only the `time_to_go`/`salvo_consensus`/`impact_time_control_accel`
   candidates + the 2-missile coordinator + the integrate!→build_env!(coordinator)→decide!(×2) loop
   (`guidance=:pn`, `autopilot=:ideal`, no seeker; `:solo` vs `:salvo`). **Confirm + pin numbers:** (i) the launch
   geometry gives a large `Δτ(:solo)` (asymmetric `t_go`); (ii) `:salvo` collapses `Δτ` (measure BOTH `Δτ` and
   per-missile miss; decide the headline — advisor #1; escalate to a binding-`a_max` framing only if the collapse
   doesn't land, the slice-12 pivot); (iii) the stretch stays **sub-`a_max`** through the run (the "can fail"
   window — advisor #2); (iv) a **CLEAN per-missile impact stamp** (the `:impacted` latch, no frame re-cross — the
   [[ewsim-missile-verifier-sampling]] discipline; if a missile misses, record + flag its CPA time, not a NaN);
   (v) **the SIGN/units** — `Δτ(:salvo) < Δτ(:solo)` AND a direct `impact_time_control_accel`/`time_to_go`/
   `salvo_consensus` recompute (advisor #5); (vi) **the solo degenerate anchor** — one missile: `:salvo`
   command `===` `:pn` command (advisor #6); (vii) **NO RNG** — the run is bit-identical replay with `t`/pos
   RNG-independent (the class-4c property, slice-12 shape — advisor #7). Write `FINDINGS.md`, pin the geometry/
   `t_d`/`K_it`/`a_max` + the `Δτ(:solo)≫Δτ(:salvo)` **RATIO** + conservative one-sided verifier bounds.
   **RE-CONSULT THE ADVISOR after the numbers land** (the landing is the one thing un-settleable from the plan —
   advisor #1: does the metric self-justify without a defender; does `a_max` bind). Forward-flag any gate-1/2/3
   seams the hand-rolled probe papers over (the coordinator-vs-truth-read seam, decision #4).

1. **Primitive green (pure, closed-form, SI, RNG-free, no LinearAlgebra).** guidance.jl: **`time_to_go`**
   (R/V_c, the receding/CPA guard → finite), **`salvo_consensus`** (`maximum`; singleton → `===` itself — the
   additivity anchor), **`impact_time_control_accel`** (PN base + impact-time-error feedback; the early⇒stretch
   sign pinned). **`COOPERATION_MODES = (:solo, :salvo)`** (add the tuple; one-list-no-drift).
   `pn_accel`/`GUIDANCE_MODES`/the existing guidance members **UNCHANGED** (byte-identity anchor). Export the three
   fns + `COOPERATION_MODES`. `test_guidance.jl` (+ coop arms, explicit `atol`): **`time_to_go` = R/V_c**
   (+ receding→finite guard); **`salvo_consensus` = max** (+ singleton `===` the additivity property; + N-element
   pin); **`impact_time_control_accel` direct-recompute** (a DIFFERENT expression — catches a transpose / sign
   slip); **at `t_go == t_d` the command `===` `pn_accel`** (the bit-exact no-op — the `:salvo`-on-a-solo bridge;
   convention 11 — via the EARLY-RETURN of `pn_accel(...)`, NOT `pn_accel + zero(Vec3)` which the −0.0+0.0→+0.0
   flip would break; if the `===` proves fragile, `atol=0.0` is an acceptable fallback since this anchor is NOT
   load-bearing for slices 1–13 additivity — those take the literal `:pn` arm); **an EARLY missile (`t_go < t_d`) gets a path-LENGTHENING command**
   (the sign anchor — an external kinematic check, not a self-calibrated round-trip). Slices 1–13 byte-identical
   through the include (golden + determinism green; no RNG added — guidance.jl stays pure).

2. **Wired — the `SalvoCoordinator` build_env! + the `:salvo` `decide!` branch + the `cooperation` rung + the
   `:datalink` kind.** `scenario.jl`: a **`:datalink` kind** (`[SalvoCoordinator]`, no mover) + N `:missile`
   interceptors + the `cooperation` fidelity key + the `k_it` guidance knob (LOAD-validated: `k_it > 0`, ≥2
   `:missile` entities for the lesson, ≥1 `:datalink`). `SalvoCoordinator.build_env!`: read all `:missile` truth,
   `time_to_go` each, `salvo_consensus` → `w.env[:salvo_t_d]` (single-writer). `Autopilot.decide!`: the NEW
   `:salvo` branch (gated `coop===:salvo && haskey(w.env,:salvo_t_d)`) → `impact_time_control_accel`; the
   non-salvo arms are the slice-10/11/12 arithmetic VERBATIM (byte-identity by construction). Record
   `comp[:t_impact]`/telemetry at the `:impact` seam. `LIVE_FIDELITY_MODES += cooperation` (radar.jl). `set_fidelity`:
   **NO new guard** — `:solo↔:salvo` is live-settable (class 4c; the `:integrator`/`:autopilot` precedent).
   - `test_missile.jl` (+ coop arms): the coordinator publishes `w.env[:salvo_t_d] == max(t_go)` over 2 missiles;
     **`:salvo` command curves an early missile toward a longer path** while **`:solo` is plain PN** (pin against
     `impact_time_control_accel`/`time_to_go`/`salvo_consensus` on a realized 2-missile world); **`Δτ(:salvo) ≪
     Δτ(:solo)` on the wire** (`guidance=:pn`/`autopilot=:ideal`/no seeker, the Lesson pin — or the
     saturation-contrast per the probe's headline); **`:solo↔:salvo` trajectories DIFFER** (not-a-dead-knob);
     **each missile's miss is vs the true `:target`, not the sibling/datalink** (`_nearest_target` — the truth-path
     invariant); **the SOLO degenerate — one interceptor: `:salvo` ≡ `:pn` bit-exact** (the additivity bridge);
     **NO `w.rng` draw under `:salvo`** (the class-4c pin — Xoshiro-unadvanced, decoy/seeker absent); loader arms +
     rejects `k_it ≤ 0` / <2 missiles / missing datalink.
   - `test_determinism.jl` (the SLICE-12 shape — NOT slice-13's RNG shape; watch-item): same-seed bit-identical
     with **NO RNG on the missile path** (pin `t` AND a per-missile pos sequence, RNG-independent); **a slice-1..13
     scenario is byte-identical** (no `:datalink`, `cooperation` unset/`:solo` → the slice-10/12 PN path + no draw
     — the additivity master-check); **`:solo↔:salvo` toggle CHANGES the trajectory** with **no RNG** (class 4c —
     write "draw-count invariance VACUOUS", do NOT claim slice-13 draws); a **slice-10 single-PN scenario replays
     BIT-IDENTICAL** after the guidance.jl/missile.jl/radar.jl edits (the mode-anchor); **`:solo↔:salvo` introduce
     is CLEAN both directions** (no topology guard — the class-4c live-safety, unlike slice-13 `:scan`).
   - `test_server.jl`: `set_fidelity :cooperation :salvo` write/**introduce-safe both directions** (class 4c, no
     guard — the `:integrator`/`:autopilot` precedent, CONTRAST slice-13 `:scan`'s reject); the `k_it` live slider
     `set_param`→tick survives (a huge `k_it` does NOT throw — "a live slider can't crash a tick"). Slices 1–13
     byte-identical.

3. **Scenario + Godot spatial-view extension + verifiers.** `scenarios/slice14_salvo.yaml`
   (`cooperation:solo` default — so the button reveals the fix; `guidance:pn`/`autopilot:ideal`/no-seeker HELD;
   2 `[BallisticMissile, Autopilot]` interceptors at asymmetric ranges + a common `[ConstantVelocity]` target + a
   `[SalvoCoordinator]` `:datalink` node; the clean-CPA + reachable-`t_d` geometry from gate 0). **Numbers probed
   against the live `load_scenario→integrate!→build_env!→decide!→telemetry` wire** + pinned (the probe's headline +
   conservative one-sided bounds).
   - Godot `Sandbox.gd`: the **existing spatial view EXTENDED** (no new mode — the slice-8..13 precedent) to render
     **N interceptors** (distinct glyphs/labels) + the common target + each missile's path. The `cooperation`
     discriminator branch is checked **before** `guidance`/`autopilot`/`seeker` (slice-14 ships ALL keys; the
     others held; the ONE button toggles `cooperation` — convention 9, the slice-13 "discrimination before the
     held keys" precedent). `_on_cooperation_pressed` (`:solo↔:salvo` ring), `COOPERATION_RUNGS`, button/badge.
     **The NEW VISUAL: the arrival-spread** — e.g. a per-missile `t_go`/`t_impact` readout + at the first impact,
     the sibling's remaining range (`:solo` = one hits while the other is far; `:salvo` = both converge together);
     the salvo missiles' **stretched S-paths** vs the solo straight-in. All readout scalars (re-confirm no Array
     telemetry / `float()`-crash). Slice-1..13 views UNTOUCHED (re-run every smoke-load + UI test — the cooperation
     branch does NOT hijack slice-11/12/13, which have no `cooperation` key → fall through).
   - `net/slice14_verify.gd` (drives the real server): `:salvo` **collapses `Δτ`** (small `max−min` of the N
     `t_impact` per the headline) with both missiles hitting the true target; `set_fidelity cooperation solo`
     **spreads** it (large `Δτ` per the headline); **`t`/per-missile `pos` bit-identical under the held seed+config**
     (RNG-free replay — the slice-12 discipline, pin `t` AND a pos sequence, NOT slice-13's RNG-affected pos);
     **`set_fidelity cooperation salvo` is ACCEPTED live** (the class-4c contrast to slice-13's `:scan` reject —
     assert it switches cleanly). Assertions on SCALARS/sequences vs the TRUE target, per missile. `S14V OK`,
     exit 0. Step counts **multiples of `emit_every`** (the drain contract).
   - `net/slice14_ui_test.gd` (mock client, no server): the handshake wires the **cooperation** cycler (NOT
     guidance/autopilot/seeker); the ring walks `:solo↔:salvo` and wraps; badge/button track; the `k_it` slider
     sends `set_param`; reset resyncs to `:solo` (`S14UI OK`).
   - `Sandbox.tscn` smoke-loaded headless against the slice-14 server (server `DONE` ⇒ scene connected, no
     GDScript errors).
   - `test_scenario.jl` + slice-14 loader testset (parses; `cooperation:solo` default PRESENT [the new key];
     `guidance:pn`/`autopilot:ideal`/no-seeker held; ≥2 `:missile` interceptors + the common `[ConstantVelocity]`
     `:target` + the `[SalvoCoordinator]` `:datalink` node present; `k_it` at a consumed comp key + a knob; loader
     rejects `k_it ≤ 0` / <2 missiles / missing datalink; the datalink is `kind === :datalink` NOT `:target`/
     `:missile` — the truth-path invariant, so `_nearest_target` ignores it).
   - The **`_draw` multi-missile / salvo-vs-solo PIXEL branch** visually confirmed via the windowed shot harness
     ([[ewsim-godot-headless]]): `:solo` = one missile impacts while the sibling is still far (spread); `:salvo` =
     both stretch and converge together (simultaneous). **(stretch, deferred)** `clients/notebooks/slice14_salvo.jl`
     Pluto (`Δτ`-vs-geometry-asymmetry / stretch-vs-`t_d` sweep — the salvo lesson as a curve); an offline
     `batch.jl` `Δτ`-vs-geometry grid (own seeded stream — but RNG-free here; the distribution path is trivial).

## Task checklist
- [ ] **0. Probe + config pin** (`M:\claud_projects\temp\slice14_probe\`: `probe*.jl` + `FINDINGS.md`,
      advisor-confirmed). Pin the geometry/`t_d`/`K_it`/`a_max` (#2/#3), the headline (#1 — spread-ratio vs
      saturation; confirm the metric self-justifies without a defender), the clean per-missile CPA/impact stamp
      (#4), the sign/units (#5), the solo degenerate anchor (#6), the no-RNG/byte-identity (#7), the
      multi-interceptor plumbing (#8), the coordinator-vs-truth-read seam (#4). **RE-CONSULT ADVISOR after the
      numbers.** Forward-flag gate-1/2/3 seams.
- [ ] **1. Primitive** — `time_to_go`/`salvo_consensus`/`impact_time_control_accel` in guidance.jl +
      `COOPERATION_MODES`; `test_guidance.jl` arms (direct-recompute, `t_go==t_d` bit-exact no-op, early⇒stretch
      sign anchor, singleton additivity). Slices 1–13 byte-identical (golden + determinism).
- [ ] **2. Wired** — `:datalink` kind + `SalvoCoordinator.build_env!` + the `:salvo` `decide!` branch + the
      `cooperation` key + the impact-time stamp; `LIVE_FIDELITY_MODES += cooperation` (NO set_fidelity guard —
      class 4c live). test_missile/test_determinism/test_server arms; slices 1–13 byte-identical.
- [ ] **3. Scenario + Godot + verifiers** — `scenarios/slice14_salvo.yaml`; Sandbox.gd multi-missile + cooperation
      cycler + arrival-spread visual; the four proofs (verify/ui/smoke/shot); `test_scenario.jl` loader arm.
      **Re-probe on the emit-grid wire** (convention 10). STATUS.md + CLAUDE.md updated. **Slice 14 COMPLETE.**

## Context / landmarks
- **The guidance lib slice 14 extends:** `core/src/guidance.jl` — `GUIDANCE_MODES`/`pn_accel`(:142)/
  `pn_accel_augmented`(:205)/`_terminal_cutoff`(:239), all pure/RNG-free/no-LinearAlgebra. The new
  `time_to_go`/`salvo_consensus`/`impact_time_control_accel` + `COOPERATION_MODES` go HERE (before radar.jl, the
  one-list precedent). `pn_accel` is REUSED UNCHANGED as the ITCG base term.
- **The Autopilot slice 14 extends:** `Autopilot.decide!` (missile.jl:270) — the OUTER-law select (`:pursuit`/
  `:pn`/`:apn`, missile.jl:335–346); slice 14 adds the `:salvo` branch (gated `coop===:salvo && haskey(w.env,
  :salvo_t_d)`), reads the coordinator's shared field. The non-salvo arms stay textually unchanged (byte-identity).
- **The build_env! shared-field precedent:** `PulseEmitter.build_env!` (esm.jl:102), `GpsSatellite.build_env!`
  (gps.jl:93), `BallisticMissile.build_env!` (missile.jl:137) — phase-2, post-`empty!(w.env)`, write cross-subsystem
  fields. `SalvoCoordinator.build_env!` is the SAME shape (single-writer `w.env[:salvo_t_d]`).
- **The count-by-kind precedent (the team set):** `count(e -> e.kind === :pulse_emitter, …)` (esm.jl:255),
  `sort!([id for … if e.kind === :esm])` (esm.jl:292), `… if e.kind === :emitter` (geolocation.jl:49). The
  coordinator gathers `kind === :missile` the SAME way — never hard-coded ids.
- **The truth-path guard:** `_nearest_target` (radar.jl:221, `kind === :target`) — consumed by radar/jammer/the
  autopilot (missile.jl:275) + CPA telemetry; interceptors are `kind === :missile`, the datalink `kind ===
  :datalink` → neither hijacks the truth target; each missile's target is the single common `:target`.
- **The mover to reuse:** `ConstantVelocity` (radar.jl:26) for the target; interceptors are `[BallisticMissile,
  Autopilot]` (the slice-9/10 force-integrated stack). The datalink node has NO mover (build_env! only).
- **The impact seam (the metric source):** `BallisticMissile.integrate!` emits `:impact` + sets `c[:impacted]`
  (missile.jl:121); slice 14 stamps `comp[:t_impact] = w.t` there. The per-missile first-CPA/impact discipline is
  [[ewsim-missile-verifier-sampling]].
- **The class-4c precedent (physics-changing, no RNG, live-settable, NO introduce-reject):** `:integrator`
  (slice 8), `:autopilot` (slice 9), the `:apn` rung (slice 12). CONTRAST slice-13 `:scan` (4b, introduce-rejected)
  — `:cooperation` is 4c, so `set_fidelity` needs NO new guard.
- **Fidelity plumbing precedent:** slice-12 `:guidance` `:apn` rung / slice-13 `:discrimination` key
  (`*_MODES` → `LIVE_FIDELITY_MODES` → `_validate_fidelity`) — `cooperation` is a new key the SAME way (but 4c,
  live-safe, no guard).
- **The kind-arming precedent:** the `:target`/`:jammer`/`:decoy` kinds (scenario.jl) — `:datalink` is a new kind
  the SAME way; the `SalvoCoordinator` is its only consumer.
- **HANDOFF** §10 item 13 (this slice — "the capstone"), §11 Tier C lines 528–534 (why (A) distributed estimation
  + (B) WTA are DEFERRED horizons, not item 13), §3 (the tick contract — phase-2 build_env! + phase-4 decide!),
  §1 (named approximations; the LOS/impact-time sign trifecta), §9 (the pure-lib reuse — `pn_accel` is the base
  term), §12 (scope is the dominant risk — one bounded slice, N=2).

## Watch-items (gotchas to bake in)
- **THE FRAMING RE-INVERSION — do NOT carry slice-13's "RNG-applies/2·N_p·N_bins/4b" language.** Slice 14 is
  truth-fed PN, NO seeker → NO `w.rng` draw → the inflection INVERTS BACK to VACUOUS (the slice-12 shape). The
  convention-4c trap running the slice-13→14 direction (opposite to slice 12→13).
- **THE CLASS IS 4c, NOT slice-13's 4b.** `:cooperation` is physics-changing with NO RNG → no draw-topology to
  flip → **introduce-SAFE, live-settable, NO set_fidelity guard** (the `:integrator`/`:autopilot`/`:apn`
  precedent). Writing "introduce-rejected like `:scan`/`:cfar`" is the false claim. "Draw-count invariance" is
  **VACUOUS** here — do NOT copy slice-13's "the sharp property to prove" language.
- **THE SHARED STATE IS `t_go`, VIA AN IDEAL DATALINK.** The coordinator is the SOLE writer of `w.env[:salvo_t_d]`;
  each Autopilot only reads it. build_env! (phase 2) survives `empty!(w.env)` → live for phase-4 decide!. Named
  approximation: zero-latency/lossless/truth-shared; consensus filtering + a degraded link are the Tier-C horizon
  (DEFERRED).
- **THE DEGENERATE ANCHOR — one missile: `:salvo` ≡ `:pn` bit-exact.** `salvo_consensus([t_go]) === t_go` → zero
  impact-time error → the feedback vanishes → the command `===` PN (convention 11's bit-exact no-op). This is the
  additivity bridge from every single-missile slice — test it.
- **THE INTERCEPTORS ARE `kind === :missile`, THE TARGET `:target`, THE DATALINK `:datalink`.** `_nearest_target`
  filters `:target`, so N missiles never target each other or the datalink node, and miss/CPA is ALWAYS vs the
  true target — assert it per missile.
- **THE LANDING IS EMPIRICAL (the slice-12/13 lesson).** Do NOT assume `:salvo` cleanly collapses `Δτ` — the probe
  measures `Δτ` AND per-missile miss AND whether `a_max` binds; picks the headline; escalates to a binding-`a_max`
  "the g-limit caps salvo compression" framing if the collapse doesn't land (the slice-12 pivot). Pin the RATIO.
- **THE SALVO CAN FAIL — pin the window.** Asymmetric-enough geometry (so `:solo` visibly spreads) + a reachable
  `t_d = max t_go` (the faster missile can stretch without saturating `a_max` before impact) + a `K_it` that
  converges before impact without oscillating; report the robust geometry/`K_it` window (a launch-range nudge
  can't erase the lesson — the slice-12 `a_max` window).
- **THE PER-TICK-MAX REFERENCE CHATTER (advisor).** A per-tick `t_d = max_j t_go_j` recompute can NON-CONVERGE:
  stretching a fast missile RAISES its `t_go = R/V_c` (lower `V_c`), so with a hot `K_it` it overshoots and STEALS
  the max → the reference missile chatters. **Default to FIXED-AT-LAUNCH `t_d`** (one-time consensus, no
  reference-switching); admit per-tick max only if the probe shows it converges. This is a gate-0 fork, not an
  implementation afterthought.
- **THE ITCG TERMINAL BLOWUP IS DISTINCT FROM THE PN ONE (advisor).** `_terminal_cutoff` guards the PN base term's
  LOS-rate→∞ as r→0; many ITCG gain forms ALSO carry a `1/t_go` (or `1/(V·t_go)`) factor in the impact-time
  feedback that blows up INDEPENDENTLY as `t_go→0`. Extend the cutoff/floor to the FEEDBACK term, not just the PN
  base — verify boundedness at gate-0/1 when the gain form is pinned (no Inf/NaN to JSON, convention 6).
- **THE IMPACT-TIME-FEEDBACK SIGN.** An EARLY missile (`t_go < t_d`) must fly a LONGER arc (delay), not a shortcut
  — pin the perpendicular-feedback sign closed-form AND `Δτ(:salvo) < Δτ(:solo)` closed-loop (the slice-10/12
  sign-pin; the LOS/impact-time trifecta, §1).
- **Keep the non-salvo path byte-identical.** The `:salvo` fetch + `impact_time_control_accel` live INSIDE the
  gated branch; `:pn`/`:apn`/`:pursuit`/seeker arms take the slice-10/11/12 arithmetic verbatim (the `+0.0`/
  spelling bit trap — slices 1–13 replay bit-identical; pin a slice-10 single-PN scenario, RNG-free).
- **`k_it`/geometry are config; validate at LOAD** (`k_it > 0`, ≥2 `:missile`, ≥1 `:datalink`); a live huge
  `k_it` just curves harder — no throw (the "a live slider can't crash a tick" discipline). `time_to_go` guards
  `V_c ≤ 0` → finite (no Inf/NaN to JSON — convention 6).
- **Stay spatial** — extend `_draw_spatial`, no new render mode (slice-8..13 precedent); the N-missile glyphs + the
  salvo-converge-vs-solo-spread paths + the per-missile `t_impact` readout IS the visual. The cooperation cycler is
  a new button state, not a new view. No Array telemetry (scalars only — the `float()`-crash watch-item).
- **Verifier drain multiples** of `emit_every`; the replay assertion pins `t` AND a per-missile pos sequence on an
  **RNG-INDEPENDENT** value (NO seeker draw — the slice-12 discipline, NOT slice-13's RNG-affected pos). Per-missile
  first-CPA/impact stamp (exclude re-cross; [[ewsim-missile-verifier-sampling]]).
