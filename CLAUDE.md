# EWSim — working notes for Claude Code

Teaching-through-play simulator for EW / air defense / GPS / missile guidance.
A headless Julia **core holds the truth**; Godot and Pluto are thin, replaceable
clients. **`HANDOFF.md` is the ground-truth design** — read it before changing
architecture, and don't relitigate its frozen decisions inside a slice.

## How to run things (Windows)

Julia 1.11.9 is installed portably and is **not on PATH**. Always go through the
wrappers so the path lives in exactly one place:

- Run tests:  `pwsh tools/test.ps1`
- Any Julia:  `pwsh tools/julia.ps1 <args>`   (e.g. `pwsh tools/julia.ps1 tools/setup.jl`)
- Godot 4.7:  `& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"`

PowerShell 5.1 mangles double quotes passed to `julia -e`. **Put Julia code in a
`.jl` file and run the file** rather than fighting inline `-e`.

## Where things live

- `core/src/` — the engine. `world.jl` (World/Entity/Vec3), `subsystem.jl` (the
  tick contract), then physics libs (`rf.jl`, `detection.jl`, ...) as slices land.
- `core/test/runtests.jl` — the contract enforcer. New model ⇒ new test here.
- `clients/godot/`, `clients/notebooks/` — thin clients. **No physics here.**
- `scenarios/*.yaml` — declarative source of truth for runs, tests, MC inputs.
- `docs/plans/` — staged plans / context / task checklists (incl. gate-0 kill records).
- `docs/STATUS.md` — the as-built ledger (detailed per-slice notes; grep `## Slice N`).
- `docs/SLICES.md` — the digest: one paragraph per slice, what its lesson was.
- `docs/DEFERRALS.md` — the backlog **and the kill list**. Read before planning a slice.
- `docs/LESSONS.md` — cross-slice method disciplines (probing, teeth, client proofs).
- `docs/CONVENTIONS.md` — the conventions' TEETH (function names, rungs, numbers) behind CLAUDE.md's hooks.

## Invariants that catch the real bugs

- **Physics lives in the core, never in a Godot script or a notebook cell.** If
  it can't run headless from `runtests.jl`, it's in the wrong place.
- **Units / frames / signs are the bug trifecta.** SI Float64 internally,
  inertial frame, quaternion body<-inertial = `[1,0,0,0]`. Test frame round-trips
  and LOS-rate signs from day one.
- **Determinism is on CPU.** Same seed + same scenario ⇒ bit-identical trace
  (enforced by `test_determinism.jl`). GPU is for bulk statistics only, never replay.
- **Approximations are switchable and named.** Every subsystem carries a
  `fidelity` knob; dialing it and watching what changes *is* the lesson. No hidden
  approximations, never simulate at carrier frequency (work at baseband / link budget).

## Tick contract (the phase map, HANDOFF §3)

Every subsystem hook runs in a fixed order each `tick!`: **phase 1** `integrate!` (movers/
airframe) → `empty!(w.env)` → **phase 2** `build_env!` (cross-subsystem fields, e.g. jamming) →
**phase 3** `observe!` (sensors) → **phase 4** `decide!` (estimators/guidance). The `empty!`
after phase 1 is a recurring gotcha (see conventions). "A missile is `integrate!` + `observe!`
+ `decide!`."


## Where the project is (2026-08-18)

**Slices 1–40 + 46 COMPLETE & green — 9184 tests** (7808 before slice 47's gate 1). **Slice 47 (THE MIDCOURSE
PHASE) is IN PROGRESS: gates 0 and 1 CLOSED** — `intercept_time` / `predicted_intercept_point` /
`midcourse_accel` in `guidance.jl` + `test_midcourse.jl`; `midcourse_k = 1.0` MEASURED; gate 2 next
(`docs/plans/slice47.md` §5). 39 and 41–45 are GATE-0 RECORDS (no code). ⚠⚠ **FIVE
CONSECUTIVE gate-0 records shipped nothing, and on 2026-08-18 the kill CRITERION itself was ruled at fault**
(the two-test rule below): 41, 44 and 45 are **ALIVE AS A MODEL**, probe code in `M:\claud_projects\temp\slice4N`;
only 42 is dead outright; 43 is BLOCKED. ⭐ **Slice 46 DISCHARGED 44's re-verdict** — it shipped 44's exact
physics as the seeker's DETECTION HORIZON, which is what the re-verdict is FOR.
HANDOFF §10 items 1–13 are DONE; 15–40 are into the §11 Tier-A horizon.

The live arc is the **missile seeker/radome family (26–40, 46)**: a seeker looks through a radome whose bend
depends on the look angle, so the missile's own motion feeds back into the line-of-sight it reports and past
a loop gain it shakes itself into a limit cycle. 27–31 built and priced the gyro feed-forward cure; 32–33
made it a field-of-view budget; 34–38 put the seeker on a **gimbal** (index, servo bandwidth, handover,
reference frame, gyro); 40 gave that gimbal **inertia**. Per-slice detail: `docs/SLICES.md`.

**46 gave the seeker a RECEIVER**: the window IS the beamwidth, so `R_acq · fov` is CONSTANT (80789 m·deg)
— a wider window costs REACH, inverting 32–36 — and a late lock is paid in MANOEUVRE AUTHORITY (2.5 → 100 %
of `a_max`), never in MISS, which reads non-monotone and backwards.

**The rule that keeps paying** (33, 34, 35, 37, 38): *aim `R̂` at the glass's worst-case slope*
(`radome_slope_worst`) and the cost — of FOV, detector window, servo bandwidth, servo frame — mostly
goes away.

## Read on demand — DO NOT preload these

Triggered by what you are about to do, not by topic. Reference them as paths; **never** as
`@`-imports (those get inlined into context eagerly and recursively, which is the whole problem
this split exists to fix).

| Before you… | Read |
|---|---|
| plan slice 46 / pick the next slice | `docs/DEFERRALS.md` — the backlog **and the kill list** |
| change architecture, frames, the wire protocol, the tick contract | `HANDOFF.md` |
| quote slice N's numbers, test names, or gate detail | `docs/STATUS.md` — grep `## Slice N` |
| recall what slice N's *lesson* was | `docs/SLICES.md` |
| write a gate-0 probe, a verifier tooth, or a HUD branch | `docs/LESSONS.md` — cross-slice method disciplines |
| touch the RNG, the wire, a fidelity rung, a live knob, a test or the Godot client | `docs/CONVENTIONS.md` — the teeth behind the one-line hooks below |
| re-run slice N's showcase / verifier | `docs/STATUS.md` §Slice N has the exact commands |

**When a slice completes**, the doc ritual writes to FIVE places, in this order: the full
as-built block into `docs/STATUS.md` (under a `## Slice N — TITLE (date)` heading), a paragraph
into `docs/SLICES.md`, the new/killed candidates into `docs/DEFERRALS.md`, any transferable
method lesson into `docs/LESSONS.md`, and into `CLAUDE.md` **only** the state line + any new dead end **as ONE LINE**
(name, VERDICT WORD, one clause of why, pointer). ⚠⚠ **`CLAUDE.md` is a REFERENCE / ROUTER file — keep
it under ~16 KB** (it is 15.2 KB after the 2026-08-18 trim, down from 25.2). It is loaded on every single
turn, and it grew by absorbing detail that belongs in `docs/DEFERRALS.md` and `docs/CONVENTIONS.md`.

## ⭐⭐⭐ TWO AIMS ⇒ TWO TESTS ⇒ TWO VERDICTS (2026-08-18 — READ BEFORE KILLING ANYTHING)

**EWSim is a teaching instrument AND a simulator** (different scenarios, models, subcomponents,
imperfections). Gate 0's kill tests measure **LESSON value only**, and slices 41–45 applied them as if they
retired the COMPONENT. Two tests now: **MODEL** — is the parameter READ by the physics each tick and correct
in its own units/signs/frames? *The only outright kill* (a knob consumed at load is a BUG). **LESSON** —
does dialing it move the authored scenario's headline metric? *Failing this kills the SLICE'S HEADLINE, not
the hardware.* ⇒ **Pass model / fail lesson = "DEAD AS A LESSON, ALIVE AS A MODEL": it ships as physics +
tests + authorable keys.** ⚠ Unchanged: the bar for NEW proposals, and slice 39's rule that a
reparameterization must not ship as an ARCHITECTURE. Detail: `docs/DEFERRALS.md` §"THE 2026-08-18
RE-VERDICT".

## Dead ends — do not rebuild (ONE LINE EACH; the detail is `docs/DEFERRALS.md`)

⚠ **Read the VERDICT WORD.** **DEAD** = the component does not exist (a cancellation, an identity, a
discretization artifact, an unread key). **DEAD AS A LESSON / ALIVE AS A MODEL** = the hardware is real
and shippable, only the headline died (see the two-test rule above). **BLOCKED** = never killed at all.
Evidence, numbers and the re-verdict table: `docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT".

- **A nulling-loop head servo** (39) — **DEAD**: an algebraic IDENTITY with the shipped feed-forward under
  transformed parameters (5.8e−09 m over 12000 ticks). ⚠ FINITE loop gain is un-killed and unproven.
- **Memory track / a coasting head** (37) — **DEAD AS A LESSON, ALIVE AS A MODEL**: a break in this arc is
  not an episode but the rest of the flight ⇒ the cure belongs to the ESTIMATOR's frozen rate, not the head.
  Three slices mis-located it.
- **A scalar rate-limited fin inside the coupled loop** (20) — **DEAD AS A LESSON**: `δ_max` structurally
  SHADOWS `δ̇_max`. The rate limit itself is SHIPPED (slice 15).
- **A second-order FIN actuator** (41) — **DEAD AS A LESSON, ALIVE AS A MODEL**, on REPARAMETERIZATION.
  ⭐⭐ **The rule to carry: a pole differs from a gain ONLY in that its phase VARIES with frequency, and that
  loop's fin command is a single 1.6488 Hz line.** ⇒ **measure the SPECTRUM of the signal a new dynamic
  element will sit on BEFORE proposing it** (`p2_spectrum.jl`).
- **A SEEKER SEARCH PATTERN** (42/43/45) — **BLOCKED, never killed**, on its precondition. ⭐⭐ **The cost of
  acquiring is the OVERLAP DEFICIT `|err| − fov`, not the pointing error** ⇒ widening the glass and
  travelling further are THE SAME ACT, and a wider window is FREE here. Its LAW (sweep floor, `t_lock`, the
  U-shaped best moment) and its three instrument bugs are in DEFERRALS. **Slice 46 supplied the horizon but
  does NOT unblock it** — what remains is a MIDCOURSE PHASE (something to fly on while blind), now the top
  of the backlog and much cheaper than it was.
- **Seeker range / SNR limits AS THE UNBLOCKER** (44) — **DEAD as the unblocker, ALIVE AS A MODEL — and
  SHIPPED by slice 46.** ⭐⭐ **A detection gate can only price a design variable if the ENGAGEMENT is
  launched OUTSIDE the sensor's horizon — a property of the WIRE** (8079 m vs 6437 m, ratio 1.255, which
  46's null cell reproduces). ⚠ Both survivors CONFIRMED on 46's shipped wire, one CORRECTED: **a late
  lock is paid in MANOEUVRE AUTHORITY and MISS cannot show it**; and **the narrow-window failures of
  32/34 are THE SERVO's** (46 binds the rate limit for 205 frames of the ACQUISITION SLEW at 30 °/s).
  ⚠⚠ **DO NOT QUOTE 44 §VII.1's “100.00 % of `a_max`”** — an r → 0 ENDGAME read; gated at r > 200 m that
  cell spends 10.45 % against 3.10 %, and the effect SURVIVES and becomes MONOTONE.
- **A rectangular / per-axis window and stop** (45) — **DEAD AS A LESSON, ALIVE AS A MODEL, both halves.**
  ⭐⭐⭐ **A TRACKER holds both axes near zero so a window's CORNERS are never visited; a SEARCH drives one
  axis to the rim BY DESIGN, which is where the corners are.** ⚠ Never quote the box's rescue without its
  control — a disc 0.7 % wider rescues it too. ⚠ It does NOT unblock the search slice.
- **An "acquisition knife-edge"** (42 gate 1) — **DEAD**: the band is `ω_LOS·dt`, ONE integration step, and
  it HALVES when `dt` halves (0.0036° against a 10° window). ⇒ **re-fly any narrow threshold effect at half
  `dt`, and read a claimed STEP against the NULL cell first.**
- **Seeker noise × the BTT roll loop** — **DEAD as a COUPLING claim** (~1000:1 low-pass); the noise itself is
  shipped (25).
- **A cubic radome curve** — **DEAD**: unbounded slope, the bend diverges, no domain.
- **An angle-domain radome corrector** — **DEAD AS THE DEFAULT, ALIVE AS A MODEL**: it needs the look angle
  and can only see it *through* the bend it is removing. ⇒ **compensate with a signal that is not itself
  corrupted by what you are compensating.**
- **Dead knobs that are BUGS, not features** — `speed` (19, FIXED — `rho` is the live lever), `k_δ` (15,
  cancels exactly), `ζ` on the lag rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude
  (21) is NOT one of these — it is a MODEL GAP**: `_integrate_6dof!` passes a CONSTANT `rho` on the path the
  whole 26–45 arc flies, and its own comment reserves the seam for ρ(z).
- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall`
  (20, 22). ⚠ **NOT component kills — that physics is SHIPPED**; only their use as the showcase SLIDER died.
- **Harness traps that cost real hours** — a verifier's `STEPS` MUST be a multiple of `emit_every` (else a
  SILENT hang); `%g`/`%.2e` are not GDScript specifiers and one bad one kills the WHOLE `%` silently;
  frame-sampling error is ASYMMETRIC (a miss samples faithfully, a HIT coarsely); an rms measured where a
  CLAMP binds cannot move and reads as a KILL; a HUD width budget is INHERITED (55 body / 30 headline) and
  asserted in PIXELS — 46's 100/96-CHAR tooth passed GREEN while every line clipped at 1152 AND 1920 px; and a
  rung that stops EMITTING makes the client's `.get(k, 0.0)` print a DEFAULTED ZERO as a PASSED TEST. Teeth: `docs/CONVENTIONS.md` §14, `docs/LESSONS.md`.

## Conventions / hard-won disciplines (ONE LINE EACH; the teeth are `docs/CONVENTIONS.md`)

**Grep `docs/CONVENTIONS.md` before acting on any of these** — the hooks below name the trap, that file
has the function names, the rungs and the measured numbers. Do NOT paraphrase a hook into a decision.

1. **A slice = 3 gates** — pure primitives → wired subsystem → scenario + Godot view + verifier.
2. **Byte-identity is the master check; slices are ADDITIVE** — and the ABSOLUTE golden catches what
   `test_determinism` structurally cannot (a draw-ORDER regression).
3. **Draw-topology hazard** — the per-look RNG draw COUNT must be invariant to rung, slider AND target.
   Gate the detection/telemetry, **never the draw**.
4. **Three fidelity classes — don't conflate them** — (a) draw-invariant RNG rungs, (b) draw-topology-
   flipping (`:cfar`), (c) physics-changing with no RNG (`:integrator`, `:autopilot`), where the
   "toggle-bit-identical" language is a **FALSE CLAIM**.
5. **A live knob can never crash a tick** — validate-at-LOAD for authored inputs, clamp-at-CONSUMER for live
   sliders; a throw inside a tick silently drops the connection.
6. **No Inf/NaN to JSON** — floors and finite-clamps; huge-but-finite ships, never ±Inf.
7. **One-list-no-drift for mode tuples** — defined ONCE in the pure lib, referenced everywhere else.
8. **Telemetry-phase gotcha** — `tick!` calls `empty!(w.env)` immediately after phase-1 `integrate!`, wiping
   any phase-1 telemetry.
9. **One lesson per scenario** — don't stack fidelities that muddy a lesson. ⚠ This governs the SHOWCASE; it
   does NOT govern what the core is allowed to model (2026-08-18 reframe).
10. **Probe empirically, THEN pin against the live wire oracle** — never against a hand-recompute.
11. **Test teeth, not tautologies** — explicit `atol`, an EXTERNAL anchor, an INDEPENDENT recompute.
12. **§9 shared libs are pure, measurement-agnostic and cross-domain** — no `w.rng`, no LinearAlgebra.
13. **The Godot client is pure — ZERO physics.** Core outputs are DRAWN from telemetry, never recomputed
    in GDScript.
14. **Every gate-3 ships FOUR proofs** — verifier, UI test, headless smoke-load, windowed shot. ⚠⚠ `STEPS`
    must be a multiple of `emit_every`; ⚠ anything computed inside `_draw` has NO headless proof.
15. **Batches own their OWN seeded stream** — never `w.rng`. Determinism is CPU.

## Running a showcase (the per-slice pattern)

Each slice `N` ships `scenarios/sliceN_*.yaml`, a `net/sliceN_verify.gd`, and a
`net/sliceN_ui_test.gd`. Exact names + the lesson to look for are in `docs/STATUS.md`.

- **Live:** `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/sliceN_*.yaml`, then
  launch Godot on `clients/godot` (the main `Sandbox.tscn` auto-detects the view). Cycle the
  fidelity button / drag the sliders to drive the lesson. The server serves **one** client then
  exits — restart per session.
- **Headless proof:** start that server, then `godot --headless --path clients/godot --script
  res://net/sliceN_verify.gd` (exit 0 = pass). The UI test needs no server:
  `… --script res://net/sliceN_ui_test.gd`.
- **All tests:** `pwsh tools/test.ps1`. (On this machine, see [[ewsim-godot-headless]] for the
  `_console.exe` / non-`pwsh` invocation caveats.)
