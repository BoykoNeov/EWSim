# EWSim — working notes for Claude Code

Teaching-through-play simulator for EW / air defense / GPS / missile guidance. A headless Julia **core holds
the truth**; Godot and Pluto are thin, replaceable clients. **`HANDOFF.md` is the
ground-truth design** — never relitigate its frozen decisions inside a slice.

## How to run things (Windows)

Julia 1.11.9 is portable and **not on PATH** — always go through the wrappers. ⚠ `pwsh` is NOT installed
here; use the call operator (see [[ewsim-godot-headless]]).

- Tests: `& tools/test.ps1` · Julia: `& tools/julia.ps1 <args>`
- Godot 4.7: `& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"`
  (⚠ the `_console.exe` build for captured stdout / exit codes)

PowerShell 5.1 mangles double quotes passed to `julia -e`. **Put Julia code in a `.jl` file and run the file.**

## Where things live

- `core/src/` — the engine. `world.jl` (World/Entity/Vec3), `subsystem.jl` (the tick contract), then physics
  libs (`rf.jl`, `detection.jl`, ...) as slices land.
- `core/test/runtests.jl` — the contract enforcer. New model ⇒ new test here.
- `clients/godot/`, `clients/notebooks/` — thin clients. **No physics here.**
- `scenarios/*.yaml` — declarative source of truth for runs, tests, MC inputs.
- `docs/plans/` — staged plans / context / task checklists (incl. gate-0 kill records).
- `docs/*.md` — the ledgers. What each one holds and when to open it: the table below.

## Invariants that catch the real bugs

- **Physics lives in the core, never in a Godot script or a notebook cell.** If it can't run headless from
  `runtests.jl`, it's in the wrong place.
- **Units / frames / signs are the bug trifecta.** SI Float64 internally, inertial frame, quaternion
  body<-inertial = `[1,0,0,0]`. Test frame round-trips and LOS-rate signs from day one.
- **Determinism is on CPU.** Same seed + same scenario ⇒ bit-identical trace (enforced by
  `test_determinism.jl`). GPU is for bulk statistics only, never replay.
- **Approximations are switchable and named.** Every subsystem carries a `fidelity` knob; dialing it and
  watching what changes *is* the lesson. Never simulate at carrier frequency (baseband / link budget).

## Tick contract (the phase map, HANDOFF §3)

Fixed order each `tick!`: **phase 1** `integrate!` (movers/airframe) → `empty!(w.env)` → **phase 2**
`build_env!` (cross-subsystem fields, e.g. jamming) → **phase 3** `observe!` (sensors) → **phase 4** `decide!`
(estimators/guidance). The `empty!` after phase 1 is a recurring gotcha (see conventions). "A missile is
`integrate!` + `observe!` + `decide!`."

## Where the project is (2026-08-31)

**Slices 1–40 + 46–50 + 52 COMPLETE & green — 18642 tests.** 39 and 41–45 are GATE-0 RECORDS (no code):
⚠⚠ **five in a row shipped nothing and the kill CRITERION itself was ruled at fault on 2026-08-18** (the
two-test rule below) — 41, 44, 45 are **ALIVE AS A MODEL** (probes in `M:\claud_projects\temp\slice4N`),
only 42 is dead outright. ⭐ **46 DISCHARGED 44, 47 DISCHARGED 43's BLOCK, 48 SHIPPED the search family and
52 ITS WIDTH** — that thread is CLOSED. **49 LEFT THE MISSILE** for a ground radar and **50 BROUGHT ITS
PHYSICS BACK**, discharging 49's own top candidate. **51 KILLED 50's own ⭐ candidate — but is NOT a "no
code" record** (below): given the MODEL test it shipped `maneuver.turn_start_s` + tests and NAMED a model
gap. Pick the next from `docs/DEFERRALS.md`.
HANDOFF §10 items 1–13 DONE; 15–40 are into the §11 Tier-A horizon.

The live arc is the **missile seeker family (26–40, 46–48, 50, 52)**: a seeker looks through a radome whose
bend depends on the look angle, so the missile's own motion feeds back into the line-of-sight it reports, and past a
loop gain it shakes itself into a limit cycle. 27–33 built, priced and budgeted the gyro cure; 34–40 put the
seeker on a **gimbal** with **inertia**; 46–48 gave it a RECEIVER, BLINDED it, then let it SEARCH, and **52
SIZED that search**. **49 stepped OUT** for a ground radar and an echo that is a SHAPE rather than a number;
**50 pointed that same shape back at the seeker.** Per-slice detail — and every number behind the lines below — is in `docs/SLICES.md`.

- **46/47/48/52 — THE CLOSED HANDOVER-AND-SEARCH THREAD** (numbers in `docs/SLICES.md`). **46 — the window
  IS the beamwidth** (a wider window costs REACH; a late lock is paid in AUTHORITY, never MISS). **47 — ⭐⭐⭐
  THE CLIFF IS THE WINDOW**: handover error = PICTURE error × TIME BLIND. **48 — ⭐⭐⭐ A SEARCH SPENDS THE
  ENGAGEMENT, NOT THE HEAD**, ⭐⭐ **ACQUISITION IS NOT A LATCH.** ⚠⚠ 47 RETRACTED its ban on
  `gimbal_fov_margin_deg`. ⚠ Authority is NOT monotone in ρ (`t_search` is the gauge); the sweep's OPENING
  SIDE is a SCENARIO property.
- **52 — ⭐⭐⭐ SIZE THE SWEEP TO THE UNCERTAINTY, DO NOT MAXIMISE IT** (48's reserve axis, the WIDTH — the
  family's first TWO-SIDED knob): too narrow never reaches at any duration, every extra degree is paid TWICE
  in travel, and **48's own authored width is on the expensive side of its own wire.** ⭐⭐⭐ **A HEAD DOES
  NOT FLY THE COVERAGE YOU AUTHOR** (0.27→0.95 of the command as the sweep widens, LESS as it speeds up) ⇒
  **a faster sweep needs a WIDER one**, and the FLOWN band — never the authored number — sets the floor.
  ⚠⚠ A view marker must separate wires differing only by the SLIDER, and its gate must be an INSTRUMENT:
  ordering cannot fix that one. ⚠ This slider's floor is NOT zero (a zero WIDTH is a search with nowhere to
  look, not 48's motionless head).
- **49 — ⭐⭐⭐ A CONSTANT ECHO CAN BE GAINED WHILE CLOSING AND NEVER LOST** ⇒ **only a SHAPE makes a
  closing target harder to see; no smaller `rcs_m2` fakes it.** ⚠ The gauge is the longest loss run WHILE
  CLOSING. ⭐⭐ **A GAUGE MUST CARRY ITS OWN WINDOW**; ⚠⚠ **a live DRAG invalidates a latch as a Reset does
  — and reaches NONE of the four gate-3 proofs.**
- **50 — ⭐⭐⭐ A TARGET CAN TAKE A LOCK BACK BY TURNING** (49's shape, under the SEEKER): the horizon
  RETREATS faster than the missile closes; the price is **the heading error it goes blind holding**, never
  the MISS — RE-EARNED, not inherited. ⚠⚠ Launching DEEPER inside the horizon makes the drop-out HARDER, so
  launch near its EDGE. ⭐⭐ **A NULL ARM AND A SUB-THRESHOLD ARM ARE DIFFERENT CONTROLS**, ⚠⚠ **a drag
  DISARMS a latched INSTANT** (a DURATION may restart, an instant may not), ⚠⚠ **the lesson's NULL and a
  dead instrument's DEFAULT are the same 0.000°** ⇒ PRESENCE decides, ⭐⭐ **A VOCABULARY IS A GAUGE.**

**The rule that keeps paying** (33, 34, 35, 37, 38): *aim `R̂` at the glass's worst-case slope*
(`radome_slope_worst`) and the cost — of FOV, detector window, servo bandwidth, servo frame — mostly
goes away.

## Read on demand — DO NOT preload these

Triggered by what you are about to do, not by topic. Reference them as paths; **never** as `@`-imports —
those inline eagerly and recursively, which is the problem this split exists to fix.

| Before you… | Read |
|---|---|
| plan a slice / pick the next one | `docs/DEFERRALS.md` — the backlog **and the kill list** |
| change architecture, frames, the wire protocol, the tick contract | `HANDOFF.md` |
| quote slice N's numbers, test names, or gate detail | `docs/STATUS.md` — the as-built ledger; grep `## Slice N` |
| recall what slice N's *lesson* was | `docs/SLICES.md` — the digest, one paragraph per slice |
| write a gate-0 probe, a verifier tooth, or a HUD branch | `docs/LESSONS.md` — cross-slice method disciplines |
| touch the RNG, the wire, a fidelity rung, a live knob, a test or the Godot client | `docs/CONVENTIONS.md` — the TEETH (function names, rungs, numbers) behind the one-line hooks below |

**When a slice completes**, the doc ritual writes FIVE places in order: the as-built block into
`docs/STATUS.md` (`## Slice N — TITLE (date)`), a plain-language paragraph into `docs/SLICES.md`,
discharged/new/killed candidates into `docs/DEFERRALS.md`, method lessons into
`docs/LESSONS.md` (⚠ fold onto the EXISTING heading when it repeats), and into `CLAUDE.md`
**only** the state line + any new dead end **as ONE LINE**. ⚠⚠ **`CLAUDE.md` is a ROUTER — keep it under
~16 KB** (trimmed 6×; **17.5 on 2026-08-31 after slice 52 — it is OVER, and the next slice must trim
BEFORE it adds**). It is loaded every turn and grows
by absorbing what belongs in the ledgers: **numbers, test names and evidence go DOWNSTREAM; verdict words
and ⚠ prohibitions stay HERE.**

## ⭐⭐⭐ TWO AIMS ⇒ TWO TESTS ⇒ TWO VERDICTS (2026-08-18 — READ BEFORE KILLING ANYTHING)

**EWSim is a teaching instrument AND a simulator.** Gate 0's kill tests measure **LESSON value only**, and
slices 41–45 applied them as if they retired the COMPONENT. Two tests now: **MODEL** — is the parameter READ
by the physics each tick, correct in its own units/signs/frames? *The only outright kill* (a knob consumed at
load is a BUG). **LESSON** — does dialing it move the authored scenario's headline metric? *Failing this
kills the SLICE'S HEADLINE, not the hardware.*
⇒ **Pass model / fail lesson = "DEAD AS A LESSON, ALIVE AS A MODEL": it ships as physics + tests + authorable
keys.** ⚠ Unchanged: the bar for NEW proposals, and slice 39's rule that a reparameterization must not ship as
an ARCHITECTURE. Detail: `docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT".

## Dead ends — do not rebuild (ONE LINE EACH; the detail is `docs/DEFERRALS.md`)

⚠ **Read the VERDICT WORD.** **DEAD** = the component does not exist (a cancellation, an identity, an
artifact, an unread key). **DEAD AS A LESSON / ALIVE AS A MODEL** = the hardware is real and shippable, only
the headline died (the two-test rule above). **BLOCKED** = never killed at all.

- **A nulling-loop head servo** (39) — **DEAD**: an algebraic IDENTITY with the shipped feed-forward under
  transformed parameters. ⚠ FINITE loop gain is un-killed.
- **Memory track / a coasting head** (37) — **DEAD AS A LESSON, ALIVE AS A MODEL**: a break here is the rest
  of the flight, not an episode ⇒ the cure is the ESTIMATOR's frozen rate, not the head.
- **A scalar rate-limited fin inside the coupled loop** (20) — **DEAD AS A LESSON**: `δ_max` structurally
  SHADOWS `δ̇_max`. The rate limit itself is SHIPPED (slice 15).
- **A second-order FIN actuator** (41) — **DEAD AS A LESSON, ALIVE AS A MODEL**, on REPARAMETERIZATION.
  ⭐⭐ **A pole differs from a gain only in that its phase VARIES with frequency, and that loop's fin command
  is ONE spectral line** ⇒ **measure the SPECTRUM before proposing a new dynamic element.**
- **A SEEKER SEARCH PATTERN** (42/43/45) — **SHIPPED BY 48, its WIDTH by 52; never killed.** ⭐⭐ **The cost
  of acquiring is the OVERLAP DEFICIT `|err| − fov`, not the pointing error.** ⚠ Do NOT re-litigate that a
  wider window is free (46 killed it) or that the miss is the gauge.
- **Seeker range / SNR limits AS THE UNBLOCKER** (44) — **DEAD as the unblocker, ALIVE AS A MODEL — SHIPPED
  by 46.** ⭐⭐ **A detection gate can only price a design variable if the ENGAGEMENT launches OUTSIDE the
  sensor's horizon** (⚠ 50: near its EDGE). ⚠ **32/34's narrow-window failures are THE SERVO's.** ⚠⚠ **DO
  NOT QUOTE 44 §VII.1's “100.00 % of `a_max`”** — an r → 0 ENDGAME read.
- **A rectangular / per-axis window and stop** (45) — **DEAD AS A LESSON, ALIVE AS A MODEL, both halves.**
  ⭐⭐⭐ **A TRACKER holds both axes near zero so a window's CORNERS are never visited; a SEARCH drives one
  axis to the rim BY DESIGN.** ⚠ Never quote the box's rescue without its control.
- **An "acquisition knife-edge"** (42 gate 1) — **DEAD**: the band is `ω_LOS·dt`, ONE integration step, and it
  HALVES when `dt` does ⇒ **re-fly any narrow threshold at half `dt`, and read a claimed STEP against NULL first.**
- **Seeker noise × the BTT roll loop** — **DEAD as a COUPLING claim** (the roll loop low-passes it away);
  the noise itself is shipped (25). **A cubic radome curve** — **DEAD**: unbounded slope, no domain.
- **An angle-domain radome corrector** — **DEAD AS THE DEFAULT, ALIVE AS A MODEL**: it sees the look angle
  only *through* the bend it removes ⇒ **compensate with a signal not corrupted by what you correct.**
- **Dead knobs that are BUGS, not features** — `speed` (19, FIXED), `k_δ` (15, cancels exactly), `ζ` on the lag
  rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude (21) is NOT one of these — it is a
  MODEL GAP**: `_integrate_6dof!` passes a CONSTANT `rho` on the path the 26–50 arc flies, and its own comment
  reserves the seam for ρ(z).
- **PRICING A RE-ACQUISITION** (51) — **DEAD AS A LESSON, ALIVE AS A MODEL** (`turn_start_s` SHIPPED): ⭐⭐⭐
  **the miss ban is a ban on a REGION, not on a GAUGE** — ⚠ the BOUNDARY past a blind coast is what does not
  reproduce (halving `dt` FLIPS whether the track returns), NOT everything past it. ⭐⭐⭐ **A lock is given
  back by the HEAD, not the ECHO.** ⚠ `head_off > fov` is `in_fov`'s DEFINITION — never a gauge.
- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall`
  (20, 22), the loss COUNT (49), miss-vs-`rcs_fineness` (50). ⚠ **NOT component kills — that physics is
  SHIPPED**; only their use as the showcase SLIDER died.
- **Harness traps that cost real hours** — `STEPS` MUST be a multiple of `emit_every` (else a SILENT hang);
  `%g`/`%.2e` are not GDScript specifiers and one bad one kills the WHOLE `%`; frame-sampling error is
  ASYMMETRIC (a miss samples faithfully, a HIT coarsely); an rms measured where a CLAMP binds reads as a KILL;
  a HUD width budget is in PIXELS and belongs to the VIEW (46, 49); a key that stops EMITTING makes
  `.get(k, 0.0)` print a DEFAULTED ZERO as a PASSED TEST — ⚠ WHICH default is a claim (49), and ⚠⚠ when the
  lesson's NULL is that value only PRESENCE separates them (50); ⚠⚠ **a PEAK-HOLD cannot see a knob that
  FELL, and NO gate-3 proof DRAGS a slider** (52) — re-arm on the drag, at the instant the new setting OWNS
  the quantity; ⚠ a probe's "has this arm drained?" test must be ARM-SPECIFIC or the next capture
  re-photographs the last one (52). Teeth: `docs/CONVENTIONS.md` §14.

## Conventions / hard-won disciplines (ONE LINE EACH; the teeth are `docs/CONVENTIONS.md`)

**Grep `docs/CONVENTIONS.md` before acting on any of these** — the hooks below name the trap; that file has the
function names, rungs and numbers. Do NOT paraphrase a hook into a decision.

1. **A slice = 3 gates** — pure primitives → wired subsystem → scenario + Godot view + verifier.
2. **Byte-identity is the master check; slices are ADDITIVE** — and the ABSOLUTE golden catches what
   `test_determinism` structurally cannot (a draw-ORDER regression).
3. **Draw-topology hazard** — the per-look RNG draw COUNT must be invariant to rung, slider AND target. Gate
   the detection/telemetry, **never the draw**.
4. **Three fidelity classes — don't conflate them** — (a) draw-invariant RNG rungs, (b) draw-topology-flipping
   (`:cfar`), (c) physics-changing with no RNG (`:integrator`, `:autopilot`), where "toggle-bit-identical" is a
   **FALSE CLAIM**.
5. **A live knob can never crash a tick** — validate-at-LOAD for authored inputs, clamp-at-CONSUMER for live
   sliders; a throw inside a tick silently drops the connection.
6. **No Inf/NaN to JSON** — floors and finite-clamps; huge-but-finite ships, never ±Inf.
7. **One-list-no-drift for mode tuples** — defined ONCE in the pure lib, referenced everywhere else.
8. **Telemetry-phase gotcha** — `tick!` calls `empty!(w.env)` immediately after phase-1 `integrate!`, wiping
   any phase-1 telemetry.
9. **One lesson per scenario** — don't stack fidelities that muddy a lesson. ⚠ Governs the SHOWCASE, NOT what
   the core is allowed to model (2026-08-18 reframe).
10. **Probe empirically, THEN pin against the live wire oracle** — never against a hand-recompute.
11. **Test teeth, not tautologies** — explicit `atol`, an EXTERNAL anchor, an INDEPENDENT recompute.
12. **§9 shared libs are pure, measurement-agnostic and cross-domain** — no `w.rng`, no LinearAlgebra.
13. **The Godot client is pure — ZERO physics.** Core outputs are DRAWN from telemetry, never recomputed in GDScript.
14. **Every gate-3 ships FOUR proofs** — verifier, UI test, headless smoke-load, windowed shot. ⚠ Anything
    inside `_draw` has NO headless proof — including which dispatch chain wins (50).
15. **Batches own their OWN seeded stream** — never `w.rng`.

## Running a showcase (the per-slice pattern)

Each slice `N` ships `scenarios/sliceN_*.yaml`, a `net/sliceN_verify.gd` and a `net/sliceN_ui_test.gd`.

- **Live:** `& tools/julia.ps1 --project=core tools/server.jl scenarios/sliceN_*.yaml`, then Godot on
  `clients/godot` (`Sandbox.tscn` auto-detects the view). ⚠ The server serves **one** client then exits.
- **Headless proof:** `godot --headless --path clients/godot --script res://net/sliceN_verify.gd`
  (exit 0 = pass, needs that server); `… sliceN_ui_test.gd` needs none. ⚠ [[ewsim-godot-headless]] has the
  `_console.exe` / non-`pwsh` caveats **and the windowed-shot recipe**.
