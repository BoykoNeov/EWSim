# EWSim — working notes for Claude Code

Teaching-through-play simulator for EW / air defense / GPS / missile guidance. A headless Julia **core holds
the truth**; Godot and Pluto are thin, replaceable clients. **`HANDOFF.md` is the
ground-truth design** — never relitigate its frozen decisions inside a slice.

## How to run things (Windows)

Julia 1.11.9 is installed portably and is **not on PATH**. Always go through the wrappers so the path lives in
exactly one place:

- Run tests:  `pwsh tools/test.ps1`
- Any Julia:  `pwsh tools/julia.ps1 <args>`   (e.g. `pwsh tools/julia.ps1 tools/setup.jl`)
- Godot 4.7:  `& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"`

PowerShell 5.1 mangles double quotes passed to `julia -e`. **Put Julia code in a `.jl` file and run the file**
rather than fighting inline `-e`.

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
  watching what changes *is* the lesson. No hidden approximations, never simulate at carrier frequency
  (work at baseband / link budget).

## Tick contract (the phase map, HANDOFF §3)

Fixed order each `tick!`: **phase 1** `integrate!` (movers/airframe) → `empty!(w.env)` → **phase 2**
`build_env!` (cross-subsystem fields, e.g. jamming) → **phase 3** `observe!` (sensors) → **phase 4** `decide!`
(estimators/guidance). The `empty!` after phase 1 is a recurring gotcha (see conventions). "A missile is
`integrate!` + `observe!` + `decide!`."

## Where the project is (2026-08-26)

**Slices 1–40 + 46 + 47 + 48 COMPLETE & green — 16154 tests.** 39 and 41–45 are GATE-0 RECORDS (no code):
⚠⚠ **five in a row shipped nothing and the kill CRITERION itself was ruled at fault on 2026-08-18** (the
two-test rule below) — 41, 44, 45 are **ALIVE AS A MODEL** (probes in `M:\claud_projects\temp\slice4N`),
only 42 is dead outright. ⭐ **46 DISCHARGED 44, 47 DISCHARGED 43's BLOCK, 48 SHIPPED the search family** —
that thread is CLOSED; pick the next slice from `docs/DEFERRALS.md`. HANDOFF §10 items 1–13 DONE; 15–40 are
into the §11 Tier-A horizon.

The live arc is the **missile seeker family (26–40, 46–48)**: a seeker looks through a radome whose bend depends
on the look angle, so the missile's own motion feeds back into the line-of-sight it reports, and past a loop gain
it shakes itself into a limit cycle. 27–33 built, priced and budgeted the gyro cure; 34–40 put the seeker on a
**gimbal** with **inertia**; 46–48 gave it a RECEIVER, BLINDED it, then let it SEARCH. Per-slice detail — and
every number behind the three lines below — is in `docs/SLICES.md`.

- **46 — the window IS the beamwidth**, so `R_acq · fov` is CONSTANT: a wider window costs REACH
  (inverting 32–36), and a late lock is paid in MANOEUVRE AUTHORITY, never in MISS.
- **47 — ⭐⭐⭐ THE CLIFF IS THE WINDOW** (the engagement flips where the handover error crosses the FOV,
  while the MISS says nothing) and ⭐⭐ **the handover error is the PICTURE error × the TIME SPENT BLIND**
  ⇒ **a midcourse budget cannot be given in m/s alone, only against a handover RANGE.** ⚠⚠ 47 RETRACTED
  its plan's ban on `gimbal_fov_margin_deg` (⚠ SERVO-CONTINGENT — only while the head has SETTLED), so it
  is off the HUD for REDUNDANCY; never quote the old "it improves while the engagement is lost" reason.
- **48 — ⭐⭐⭐ A SEARCH SPENDS THE ENGAGEMENT, NOT THE HEAD**: below a slew-rate floor it never acquires,
  and that whole region is BIT-IDENTICAL to a frozen head (the miss ban's strongest form yet); above it
  acquisition is CERTAIN, PINNED at 100 % of `a_max`, and it still misses. ⚠ Authority is NOT
  monotone in ρ (it saturates, then falls); the monotone gauge is `t_search`. ⭐⭐ **ACQUISITION IS NOT A
  LATCH** (a rim-graze lock is consumed and buys nothing), and ⚠ the sweep's OPENING SIDE is a SCENARIO property —
  48 flips 47's error direction so it opens AWAY; never "simplify" that back.

**The rule that keeps paying** (33, 34, 35, 37, 38): *aim `R̂` at the glass's worst-case slope*
(`radome_slope_worst`) and the cost — of FOV, detector window, servo bandwidth, servo frame — mostly
goes away.

## Read on demand — DO NOT preload these

Triggered by what you are about to do, not by topic. Reference them as paths; **never** as
`@`-imports — those inline eagerly and recursively, which is the problem this split exists to fix.

| Before you… | Read |
|---|---|
| plan a slice / pick the next one | `docs/DEFERRALS.md` — the backlog **and the kill list** |
| change architecture, frames, the wire protocol, the tick contract | `HANDOFF.md` |
| quote slice N's numbers, test names, or gate detail | `docs/STATUS.md` — the as-built ledger; grep `## Slice N` |
| recall what slice N's *lesson* was | `docs/SLICES.md` — the digest, one paragraph per slice |
| write a gate-0 probe, a verifier tooth, or a HUD branch | `docs/LESSONS.md` — cross-slice method disciplines |
| touch the RNG, the wire, a fidelity rung, a live knob, a test or the Godot client | `docs/CONVENTIONS.md` — the TEETH (function names, rungs, numbers) behind the one-line hooks below |
| re-run slice N's showcase / verifier | `docs/STATUS.md` §Slice N has the exact commands |

**When a slice completes**, the doc ritual writes FIVE places in order: the as-built block into
`docs/STATUS.md` (a `## Slice N — TITLE (date)` heading), a paragraph into `docs/SLICES.md`, new/killed
candidates into `docs/DEFERRALS.md`, any transferable method lesson into `docs/LESSONS.md`, and into
`CLAUDE.md` **only** the state line + any new dead end **as ONE LINE** (name, VERDICT WORD, one clause of
why, pointer). ⚠⚠ **`CLAUDE.md` is a REFERENCE / ROUTER — keep it under ~16 KB** (25.2 → 15.2 KB on
2026-08-18, crept to 17.2, re-trimmed to 15.4 on 2026-08-26). It is loaded every single turn and grows by
absorbing what belongs in the ledgers: **numbers, test names and evidence go DOWNSTREAM; verdict words and ⚠
prohibitions stay HERE.**

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

⚠ **Read the VERDICT WORD.** **DEAD** = the component does not exist (a cancellation, an identity, a
discretization artifact, an unread key). **DEAD AS A LESSON / ALIVE AS A MODEL** = the hardware is real and
shippable, only the headline died (the two-test rule above). **BLOCKED** = never killed at all.

- **A nulling-loop head servo** (39) — **DEAD**: an algebraic IDENTITY with the shipped feed-forward under
  transformed parameters. ⚠ FINITE loop gain is un-killed and unproven.
- **Memory track / a coasting head** (37) — **DEAD AS A LESSON, ALIVE AS A MODEL**: a break here is not an
  episode but the rest of the flight ⇒ the cure is the ESTIMATOR's frozen rate, not the head (3 slices missed it).
- **A scalar rate-limited fin inside the coupled loop** (20) — **DEAD AS A LESSON**: `δ_max` structurally
  SHADOWS `δ̇_max`. The rate limit itself is SHIPPED (slice 15).
- **A second-order FIN actuator** (41) — **DEAD AS A LESSON, ALIVE AS A MODEL**, on REPARAMETERIZATION.
  ⭐⭐ **A pole differs from a gain ONLY in that its phase VARIES with frequency — and that loop's fin command
  is a single spectral line** ⇒ **measure the SPECTRUM a new dynamic element will sit on BEFORE proposing it**
  (`p2_spectrum.jl`).
- **A SEEKER SEARCH PATTERN** (42/43/45) — **SHIPPED BY SLICE 48; never killed.** ⭐⭐ **The cost of acquiring
  is the OVERLAP DEFICIT `|err| − fov`, not the pointing error.** ⚠ Do NOT re-litigate that a wider window is
  free (46 killed it) or that the miss is the gauge. Its surviving candidates: `docs/DEFERRALS.md`.
- **Seeker range / SNR limits AS THE UNBLOCKER** (44) — **DEAD as the unblocker, ALIVE AS A MODEL — SHIPPED
  by slice 46.** ⭐⭐ **A detection gate can only price a design variable if the ENGAGEMENT is launched OUTSIDE
  the sensor's horizon — a property of the WIRE.** ⚠ Both its survivors hold on 46's wire (46's
  authority-not-miss line above; **32/34's narrow-window failures are THE SERVO's**).
  ⚠⚠ **DO NOT QUOTE 44 §VII.1's “100.00 % of `a_max`”** — an r → 0 ENDGAME read; gated at r > 200 m the
  cell reads far lower, though the effect SURVIVES.
- **A rectangular / per-axis window and stop** (45) — **DEAD AS A LESSON, ALIVE AS A MODEL, both halves.**
  ⭐⭐⭐ **A TRACKER holds both axes near zero so a window's CORNERS are never visited; a SEARCH drives one axis
  to the rim BY DESIGN, which is where the corners are.** ⚠ Never quote the box's rescue without its control
  — a disc a fraction of a percent wider rescues it too. ⚠ It does NOT unblock the search slice.
- **An "acquisition knife-edge"** (42 gate 1) — **DEAD**: the band is `ω_LOS·dt`, ONE integration step, and it
  HALVES when `dt` does ⇒ **re-fly any narrow threshold at half `dt`, and read a claimed STEP against NULL first.**
- **Seeker noise × the BTT roll loop** — **DEAD as a COUPLING claim** (the roll loop low-passes it away); the
  noise itself is shipped (25).
- **A cubic radome curve** — **DEAD**: unbounded slope, the bend diverges, no domain.
- **An angle-domain radome corrector** — **DEAD AS THE DEFAULT, ALIVE AS A MODEL**: it needs the look angle and
  can only see it *through* the bend it removes ⇒ **compensate with a signal not corrupted by what you correct.**
- **Dead knobs that are BUGS, not features** — `speed` (19, FIXED — `rho` is the live lever), `k_δ` (15, cancels
  exactly), `ζ` on the lag rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude (21) is NOT
  one of these — it is a MODEL GAP**: `_integrate_6dof!` passes a CONSTANT `rho` on the path the whole 26–45 arc
  flies, and its own comment reserves the seam for ρ(z).
- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall` (20,
  22). ⚠ **NOT component kills — that physics is SHIPPED**; only their use as the showcase SLIDER died.
- **Harness traps that cost real hours** — a verifier's `STEPS` MUST be a multiple of `emit_every` (else a SILENT
  hang); `%g`/`%.2e` are not GDScript specifiers and one bad one kills the WHOLE `%` silently; frame-sampling error
  is ASYMMETRIC (a miss samples faithfully, a HIT coarsely); an rms measured where a CLAMP binds cannot move and
  reads as a KILL; a HUD width budget is INHERITED and asserted in PIXELS, so 46's CHARACTER-count tooth passed
  GREEN while every line clipped; and a rung that stops EMITTING makes the client's `.get(k, 0.0)` print a
  DEFAULTED ZERO as a PASSED TEST. Teeth: `docs/CONVENTIONS.md` §14, `docs/LESSONS.md`.

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
14. **Every gate-3 ships FOUR proofs** — verifier, UI test, headless smoke-load, windowed shot. ⚠⚠ `STEPS` must be
    a multiple of `emit_every`; ⚠ anything computed inside `_draw` has NO headless proof.
15. **Batches own their OWN seeded stream** — never `w.rng`.

## Running a showcase (the per-slice pattern)

Each slice `N` ships `scenarios/sliceN_*.yaml`, a `net/sliceN_verify.gd` and a `net/sliceN_ui_test.gd`.

- **Live:** `pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/sliceN_*.yaml`, then Godot on
  `clients/godot` (`Sandbox.tscn` auto-detects the view). ⚠ The server serves **one** client then exits.
- **Headless proof:** `godot --headless --path clients/godot --script res://net/sliceN_verify.gd`
  (exit 0 = pass, needs that server); `… sliceN_ui_test.gd` needs none.
  ⚠ See [[ewsim-godot-headless]] for the `_console.exe` / non-`pwsh` caveats on this machine.
