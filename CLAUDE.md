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
- `docs/plans/` — staged plans / context / task checklists (incl. gate-0 kill records); `docs/*.md` are the
  ledgers (which one, when: the table below).

## Invariants that catch the real bugs

- **Physics lives in the core, never in a Godot script or a notebook cell** — if it can't run headless from
  `runtests.jl`, it's in the wrong place.
- **Units / frames / signs are the bug trifecta.** SI Float64, inertial frame, quaternion body<-inertial =
  `[1,0,0,0]`; test frame round-trips and LOS-rate signs from day one.
- **Determinism is on CPU.** Same seed + scenario ⇒ bit-identical trace (`test_determinism.jl`); GPU is for
  bulk statistics, never replay.
- **Approximations are switchable and named.** Every subsystem carries a `fidelity` knob, and dialing it
  *is* the lesson. Never simulate at carrier frequency (baseband / link budget).

## Tick contract (the phase map, HANDOFF §3)

Fixed order each `tick!`: **phase 1** `integrate!` (movers/airframe) → `empty!(w.env)` → **phase 2**
`build_env!` (cross-subsystem fields, e.g. jamming) → **phase 3** `observe!` (sensors) → **phase 4** `decide!`
(estimators/guidance). "A missile is `integrate!` + `observe!` + `decide!`."

## Where the project is (2026-09-07)

**Slices 1–40 + 46–50 + 52–55 COMPLETE & green — 20158 tests.** 39 and 41–45 are GATE-0 RECORDS (no code) —
⚠⚠ **five in a row shipped nothing and the kill CRITERION was ruled at fault on 2026-08-18** (the two-test
rule below); 41/44/45 are **ALIVE AS A MODEL** (probes in `W:\temp\claude\slice4N`), only 42 is dead
outright. ⭐ **46 DISCHARGED 44, 47 DISCHARGED 43's BLOCK, 48 SHIPPED the search family and 52 ITS WIDTH** —
CLOSED. **49/50 MADE THE ECHO A SHAPE, 53 ITS FORE/AFT ASYMMETRY**, and ⭐⭐⭐ **54 DISCHARGED 53's OWN
give-up candidate, and 55 TURNED THE WINDOW ON ITS SIDE** (45's window half, at held aperture).
**51 KILLED 50's ⭐ candidate but is NOT a "no code" record** — it shipped
`maneuver.turn_start_s` + tests and NAMED a model gap. Pick the next from `docs/DEFERRALS.md`.
HANDOFF §10 items 1–13 DONE; 15–40 are §11 Tier-A.

The **missile seeker family (26–40, 46–48, 50, 52)** ran the radome→gimbal→receiver→search arc and is
CLOSED. **49/50/53 moved to the ECHO ITSELF** — a shape, that shape under a seeker, then its fore/aft
ASYMMETRY — **54 moved to the TRACKER that reads it, and 55 to the WINDOW's own SHAPE.** Per-slice detail — and every number behind the
lines below — is in `docs/SLICES.md`.

- **46/47/48/52 — THE CLOSED HANDOVER-AND-SEARCH THREAD** (verdicts in `docs/SLICES.md`; teeth in `docs/LESSONS.md`). ⭐⭐⭐ **THE CLIFF IS THE WINDOW**; **A SEARCH SPENDS THE ENGAGEMENT, NOT THE HEAD**; **SIZE THE SWEEP TO THE UNCERTAINTY** ⇒ **a faster sweep needs a WIDER one.** ⚠⚠ 47 RETRACTED its ban on `gimbal_fov_margin_deg`. ⚠ Authority is NOT monotone in ρ; 52's floor is NOT zero.
- **49/50 — THE ECHO AS A SHAPE** (detail in `docs/SLICES.md`). ⭐⭐⭐ **ONLY A SHAPE MAKES A CLOSING TARGET HARDER TO SEE**; **A TARGET CAN TAKE A LOCK BACK BY TURNING**, priced in the heading error it goes blind holding, never the MISS. ⭐⭐ **A GAUGE MUST CARRY ITS OWN WINDOW**; **A VOCABULARY IS A GAUGE.** ⚠⚠ Launch near the horizon's EDGE; a live DRAG invalidates a latch as a Reset does and DISARMS a latched INSTANT; the lesson's NULL and a dead instrument's DEFAULT read the same ⇒ PRESENCE decides.
- **53 — ⭐⭐⭐ A TAIL LOBE: ONE END OF A PASS IS UNTOUCHABLE AND THE OTHER IS THE SLIDER.** A brighter rear hemisphere ⇒ the same target on the same fly-past is held FAR FURTHER OUT running away than it was ever seen coming in — and no `rcs_m2`/`rcs_fineness` fakes it, both being fore/aft SYMMETRIC and moving BOTH ends. ⭐⭐⭐ **A RULE COUNTED IN SAMPLES CHANGES MEANING WHEN THE SAMPLE RATE DOES** ⇒ the gauge could not live in the client. ⭐⭐⭐ **DECLARE THE SELECTION RULE BEFORE THE FLIGHTS AND PUBLISH THE LOSERS** — the obvious seed lost. ⚠⚠ **THE METRES ARE A JOINT PROPERTY OF THE LOBE AND THE TRACKER** — the SIGN is physics, the SIZE is not. ⚠ The NULL is fading NOISE, never zero. ⚠⚠ **A FRAME-HANDLER accumulator has NO headless proof AND no shot either**; ⚠ a CROSSING pass needs a downrange FLOOR.
- **54 — ⭐⭐⭐ THERE IS NO RIGHT AMOUNT OF PATIENCE: THE GIVE-UP RULE IS SET BY HOW DIRTY THE PICTURE IS.** Over a CFAR picture the tracker must choose its own cell and CAN BE WRONG (the point path is handed TRUTH, so patience is free there). ⭐⭐ **ALIVE = NEAREST-AND-GATED, DEAD = LOUDEST-AND-UNGATED — that asymmetry IS the two-sidedness.** ⭐⭐⭐ **WHEN THE ARGMAX IS NOISE, SHIP THE CURVE** (N shadow arms on ONE pass — cheap, PAIRED, and it must draw NOTHING). ⭐⭐ **A rule counted in LOOKS is `dt`-invariant when the look cadence is** (prove it on the PICTURE, not on an argmax). ⭐⭐⭐ **A pre-registered rule earns authority the first time it REFUSES something.** ⚠⚠ Truth reaches the GAUGE, never the TRACKER. ⚠⚠ **THE COUNT OF LOOKS IS A JOINT PROPERTY OF THE RULE, THE GATE AND THE BAND** — the DIRECTION is physics, the COUNT is not. ⚠⚠ `cnr_db` is NOT a false-alarm source — **clutter under CFAR is a MASKER**; `pfa` is the mover. ⚠⚠ **`bad` is NOT monotone in the dirtiness** (two roads: COAST off vs be CAPTURED) ⇒ gauge the NET, never a half. ⚠⚠ **BEING WRONG NEEDS A DROP FIRST** ⇒ never put a tooth on an UNMEASURED arm.

**The rule that keeps paying** (33, 34, 35, 37, 38): *aim `R̂` at the glass's worst-case slope*
(`radome_slope_worst`) and the cost — of FOV, detector window, servo bandwidth, servo frame — mostly
goes away.

## Read on demand — DO NOT preload these

Triggered by what you are about to do, not by topic. Reference them as paths, **never** as `@`-imports —
those inline eagerly and recursively, which is the problem this split exists to fix.

| Before you… | Read |
|---|---|
| propose a knob, a slider or a slice candidate; write a gate-0 kill record; quote a past slice's ⚠ | `docs/PROHIBITIONS.md` — everything already ruled on, and the REASONING behind the names below |
| plan a slice / pick the next one | `docs/DEFERRALS.md` — the backlog **and the kill list** |
| change architecture, frames, the wire protocol, the tick contract | `HANDOFF.md` |
| quote slice N's numbers, test names, or gate detail | `docs/STATUS.md` — the as-built ledger; grep `## Slice N` |
| recall what slice N's *lesson* was | `docs/SLICES.md` — the digest, one paragraph per slice |
| write a gate-0 probe, a verifier tooth, or a HUD branch | `docs/LESSONS.md` — cross-slice method disciplines |
| touch the RNG, the wire, a fidelity rung, a live knob, a test or the Godot client | `docs/CONVENTIONS.md` — the TEETH (function names, rungs, numbers) behind the one-line hooks below |

**When a slice completes**, the doc ritual writes SIX places in order: the as-built block into
`docs/STATUS.md` (`## Slice N — TITLE (date)`), a plain-language paragraph into `docs/SLICES.md`,
discharged/new/killed candidates into `docs/DEFERRALS.md`, method lessons into `docs/LESSONS.md`
(⚠ fold onto the EXISTING heading when it repeats), **every new ⚠ prohibition — with its reasoning,
its numbers and its slice cite — into `docs/PROHIBITIONS.md`**, and into `CLAUDE.md` **only** the
state line + any new dead end's NAME AND VERDICT WORD, folded into an EXISTING line.
⚠⚠ **`CLAUDE.md` is a ROUTER — target ~16 KB** (⚠⚠ **16.5 KB — OVER, and slice 55 added +0.27 to a file that was already over at 16.3.** The structural move below is now DUE, not optional; 15.4 after the 2026-09-06 split, +0.7 TRIGGER block; 9 prose
trims before it). **Numbers, test names, evidence — and now the REASONING behind a prohibition — go
DOWNSTREAM; only the state line, the verdict words, the trip-wire NAMES and the conventions stay HERE.**
⚠⚠ **PROSE-TRIMMING WILL NOT SAVE THIS FILE A SECOND TIME.** If it goes over again the answer is another
structural move — the per-slice bullets under "Where the project is" are the next candidate (~4.4 KB) —
never shaving a ⚠. Detail: `docs/LESSONS.md`.

## ⭐⭐⭐ TWO AIMS ⇒ TWO TESTS ⇒ TWO VERDICTS (2026-08-18 — READ BEFORE KILLING ANYTHING)

**EWSim is a teaching instrument AND a simulator.** Gate 0's kill tests measure **LESSON value only**, and
slices 41–45 applied them as if they retired the COMPONENT. Two tests now: **MODEL** — is the parameter READ
by the physics each tick, correct in its own units/signs/frames? *The only outright kill* (a knob consumed at
load is a BUG). **LESSON** — does dialing it move the authored scenario's headline metric? *Failing this
kills the SLICE'S HEADLINE, not the hardware.*
⇒ **Pass model / fail lesson = "DEAD AS A LESSON, ALIVE AS A MODEL": it ships as physics + tests + authorable
keys.** ⚠ Unchanged: the bar for NEW proposals, and slice 39's rule that a reparameterization must not ship as
an ARCHITECTURE. Detail: `docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT".
⭐⭐⭐ **AND A SLIDER IS ONE TRIGGER, NOT THE ONLY ONE (2026-09-06).** A lesson needs a TRIGGER and a
CONTRAST: **SLIDER** (dial it, the metric moves) · **RIVAL** (two designs; the worse fails for a STATED
reason) · **REGIME** (same part, inert in one mode and decisive in another — incl. two limits where only
one binds) · **CURVE** (the response REVERSES; the turning point IS the lesson) · **NULL** (the measured
absence, shipped WITH its bound). ⚠⚠ **`INSTRUMENT` is NOT one of them** — an identity, an artifact or an
unread key teaches about the SIMULATOR and has NOTHING to author. ⇒ **"failed the SLIDER test" was never
"failed the LESSON test".** Tags: `docs/PROHIBITIONS.md`; cost + evidence: `docs/DEFERRALS.md` §BUILD LIST.

## Dead ends — do not rebuild (NAMES ONLY; the ruling and its reasoning are `docs/PROHIBITIONS.md`)

⚠ **Read the VERDICT WORD.** **DEAD** = the component does not exist (a cancellation, an identity, an
artifact, an unread key). **DEAD AS A LESSON / ALIVE AS A MODEL** = the hardware is real and shippable, only
the headline died (the two-test rule above). **BLOCKED** = never killed at all. **✅** = SHIPPED since, and
listed only so it is not re-proposed as open.
⚠⚠ **A name below is a TRIP-WIRE, not the ruling** — it exists so a re-proposal stops mid-sentence. Open
`docs/PROHIBITIONS.md` before proposing, re-proposing, reviving or quoting any of them.

- **DEAD** — **a nulling-loop head servo** (39); **seeker noise × the BTT roll loop** as a COUPLING claim; **a cubic radome curve**; **an "acquisition knife-edge"** (42 gate 1).
- **DEAD AS A LESSON, ALIVE AS A MODEL** — **memory track / a coasting head** (37); **a scalar rate-limited fin in the coupled loop** (20); **a second-order FIN actuator** (41); **a rectangular / per-axis window and stop** (45 — ⚠ the WINDOW half ✅ SHIPPED by 55, only the STOP is open); **PRICING A RE-ACQUISITION** (51). **DEAD AS THE DEFAULT, ALIVE AS A MODEL** — **an angle-domain radome corrector**.
- **✅ SHIPPED — never re-propose as open** — **a SEEKER SEARCH PATTERN** (42/43/45 ⇒ 48, its WIDTH 52); **seeker range / SNR limits** (44 ⇒ 46); **a TAIL LOBE** (49/50 ⇒ 53); **a GIVE-UP RULE AS THE SLIDER** (53 ⇒ 54); **a FAN-BEAM WINDOW** (45 ⇒ 55, `Ω` HELD — ⚠ a circle is a POINT on the aspect axis, not the baseline). ⚠ Each carries what it did NOT discharge.
- **Dead knobs that are BUGS, not features** — `speed` (19), `k_δ` (15), `ζ` on the lag rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude (21) was a MODEL GAP, ✅ FIXED 2026-09-06** — `:atmosphere` was inert on `:six_dof` for 30 slices.
- **Disqualified by non-monotonicity** (the showcase SLIDER died; the physics is SHIPPED) — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall` (20, 22), the loss COUNT (49), miss-vs-`rcs_fineness` (50), `bad`-vs-`pfa` (54).
- **Harness traps that cost real hours** and **HUD / view traps** — ⚠⚠ each is a LIST, not a line, and every entry cost real hours: read `docs/CONVENTIONS.md` §16 (names) / §14 (teeth) before writing a probe, a verifier tooth, a gate-3 proof or a HUD branch. ⚠ Retractions: `docs/PROHIBITIONS.md` §6.

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
