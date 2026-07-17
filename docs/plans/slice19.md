# Slice 19 — the inner α/g autopilot: the airframe flies its own command (§11 Tier-A)

**The slice that makes the coupled airframe STEER ITSELF — and the first time an aerodynamic limit,
not a kinematic number, decides whether the missile hits.** Slice 17 gave the missile a body lift that
turns the flight path, but the fin δ was a FIXED authored trim: the airframe curved, it did not *aim*.
Slice 19 closes the inner loop — the guidance command is inverted through the aero into an angle-of-attack
command, and from there into a fin deflection: **`a_cmd → α_cmd → δ`**. The missile finally flies its own
PN command *through the airframe* rather than by fiat.

The payoff is the lesson slices 15/16/17 were all banking toward: the **flight-condition-dependent g-limit**
`a_max_aero = Q·S·C_Lα·α_max/m`. Slices 10/12 capped the missile with a *number* (`a_max`, authored). Here
the cap is a *physical consequence* — the airframe can only generate the lift its dynamic pressure and its
stall-limited α allow. Fly slow and it cannot pull, no matter what the guidance asks for.

**ORDERING NOTE.** `slice17.md`/HANDOFF §11 named this slice "18"; the user-directed terrain + 3-D insertion
(2026-07-14) took that number and this shifted to **19** with its trigger intact (`slice18.md:143`,
`STATUS.md:2126`). Nothing about the content moved — only the number.

Source of truth: HANDOFF §11 Tier-A (the "6-DOF airframe + actuator/fin dynamics" entry — slice 15 = the
actuator/fin half, 16 = rotation, 17 = the α→lift coupling, **19 = the closed inner loop**), §2 (the
cascade: outer guidance law → inner autopilot), §3 (the tick contract), §1 (named approximations; the
units/frames/signs trifecta). Slice 17's `airframe.jl` + `_integrate_coupled!` are the direct base.

---

## Two things in the code contradict the plan-of-record — read these FIRST

Both were found by reading the source, both were advisor-reconciled, and both change what this slice is.
The pattern is the slice-17 one recurring (a forward-promise written *before* the work turned out to need a
fresh design — there, `rk4_rot`'s "reuses the closure" became a fresh `rk4_coupled`). **Do not inherit the
plan-of-record's wording over the code.**

### 1. `:a_ctrl` must STAY OUT of the coupled force — the slice-17 comment is WRONG

`missile.jl:164` says: *"guidance→lift coupling via `:a_ctrl` in the joint force is slice 18."* **Do not do
this.** It would destroy the lesson.

The point-mass path (`missile.jl:115`) adds the autopilot's `:a_ctrl` straight into the force closure — a
control acceleration by fiat, bounded only by the authored `a_max`. The coupled path (`_integrate_coupled!`,
`missile.jl:168`) deliberately omits it. **That omission is the load-bearing design, not a gap:** the whole
content of `a_max_aero` is that the achievable maneuver accel *IS* the lift ceiling. Add `a_ctrl` back into
the joint force and the missile gets lift **plus** a direct fixed-`a_max` control force — it over-maneuvers,
the aero ceiling never binds, and you have silently rebuilt the point-mass plant wearing an airframe costume.
(The exact shape of slice-15's `k_δ`-cancellation trap and slice-16's false-fidelity trap — **third
occurrence in this arc**.)

So: **the α autopilot writes a δ command; the coupled force path stays `a_ctrl`-free.** Fix the stale comment
at `missile.jl:164` as part of gate 2.

### 2. The "two Tier-A halves join" promise is OVERSOLD — δ is a scalar, `FinState.δ` is a Vec3

Every prior plan says slice 19 is where "the slice-15 fin state δ feeds the `Cmδ·δ` moment term — the two
Tier-A halves join." **They do not compose as written.** `FinState.δ` (`guidance.jl:118`) is a **`Vec3`** —
slice-15's planar magnitude-limited deflection *abstraction*, clamped by `clamp_accel`, living in the 3-D
accel frame. `pitch_moment` (`airframe.jl:78`) takes **`delta::Float64`** — a scalar pitch-plane deflection
in rad. Different frames, different dimensionality; the Vec3 servo is not literally reusable.

**The resolution (advisor):** command a **scalar δ** through the existing `af_delta` → `pitch_moment` path
and **do not touch `FinState` at all**. The halves join *conceptually* — a fin-commanded coupled airframe is
exactly what slice 15 banked δ for — but the Vec3 servo abstraction is a different frame that this slice does
not reuse. Say so in the code comments; do not repeat the "halves join" phrasing as if it were a wiring job.

**This collapses the scope question.** Once "the slice-15 join" means "reuse the scalar δ path" (trivial)
rather than "wire in the Vec3 rate-limited servo" (hard, and a *different* lesson), the plan-of-record's
bundle is genuinely **one lesson**. So — unlike slices 15/16/17 — **no formal scope split.** Instead, ISOLATE
the rate limit: either keep any scalar servo's `δ̇_max` non-binding in the showcase (the slice-15
"three separable numbers" discipline), or defer the servo entirely (named below). `a_max_aero` stays the
clean headline (convention 9).

### 3. (Found while planning) ρ is CONSTANT — "high altitude" is NOT a Q lever in this codebase

Every prior plan phrases the lesson as *"at low Q (**slow / high-altitude**) the missile can't pull enough g."*
**Half of that is false here.** `rho` is a per-missile authored constant (`missile.jl:88`,
`scenario.jl:318`) — `drag_accel`/`total_accel`/`AirframeParams` all take it as a fixed number, and NOTHING
in the project makes ρ a function of altitude (it is a named approximation shared with dynamics.jl,
`airframe.jl:34`). `Q = ½ρV²` with ρ constant ⇒ **only SPEED moves Q.** Climbing does not thin the air.

**The lever is therefore V, not altitude.** Two honest routes, gate-0 picks:
- **(a) SPEED (recommended).** A launch-speed knob (and/or drag ON so the missile *bleeds* speed and
  `a_max_aero` FALLS through the engagement — the endgame g-limit tightens exactly when the demand peaks).
  No new physics, no byte-identity risk, and the dynamic version is a genuinely better lesson.
- **(b) An exponential atmosphere** `ρ(z) = ρ₀·exp(−z/H)`. Physically the *right* answer and it would make
  "high altitude" true — but it is NEW physics touching the shared drag path, it changes what `:rho` means,
  and it is a slice of its own. **DEFERRED (named below).**

Take (a). And **fix the phrasing everywhere it lands** (STATUS/HANDOFF/comments): "at low **dynamic
pressure** (slow)", never "slow / high-altitude", until (b) exists. §1 forbids hidden approximations; this is
one that has been quietly propagating through three plans.

---

## The scope

- **The inner loop only.** The outer laws (`:guidance` = pursuit/pn/apn) are UNTOUCHED — they still produce
  `a_cmd` exactly as slices 10/12 do. Slice 19 replaces what happens *below* `a_cmd`.
- **Pitch plane ONLY** (the slice-16/17 reduction unchanged). A pitch-plane α autopilot can only generate
  x–z acceleration ⇒ **any out-of-plane `a_cmd` component is DISCARDED** — a named §1 approximation (advisor)
  that CONSTRAINS the scenario: the engagement must be planar (all y = 0, target maneuver in x–z).
- **Closed-loop δ** — the fin is commanded every tick by the autopilot, replacing slice-17's fixed trim.
- **The aero limit is the lesson**, and it must be the thing that BINDS: `a_max_aero < demand < a_max` at the
  showcase operating point (gate-0 confirms — see the isolation discipline below).

The law (the NEW chain; the outer law, the moment, and the lift are all slice-10/16/17 verbatim):

    a_cmd                                              (Vec3 — the outer law, post `clamp_accel(a_dem, a_max)`)
    γ  = atan(v_z, v_x),  n̂ = (−sin γ, 0, cos γ)       (the lift direction — airframe.jl `lift_accel`'s perp)
    a_perp = dot(a_cmd, n̂)                             (SIGNED scalar; out-of-plane DISCARDED — named approx)
    Q  = ½·ρ·V²,   Q_eff = max(Q, Q_FLOOR)             (← THE CRASH-SAFETY SITE, convention 5)
    α_cmd  = clamp(a_perp·m / (Q_eff·S·C_Lα), ±α_max)  (← THE AERO LIMIT — the clamp IS `a_max_aero`)
    δ_cmd  = the α-loop (gate-0 picks — see below)
    →  pitch_moment(α, δ, q, V, p) → (θ, q) → α = θ−γ → lift_accel → γ̇      (slice 16/17, UNCHANGED)

**`a_max_aero = Q·S·C_Lα·α_max/m` is exactly the accel the α_max clamp permits** — the clamp is not a
safety hack bolted on beside the lesson, it *is* the lesson expressed in code. Worth a comment saying so.

**The δ law is the one thing the plan cannot settle — gate 0 decides (advisor).** Two candidates:
- **Static trim inversion:** `δ_cmd = −(Cmα/Cmδ)·α_cmd` — the exact inverse of `trim_alpha`
  (`airframe.jl:152`). Clean, closed-form, and with slice-17's overdamped `Cmq = −150` it may well settle.
  But it is open-loop *in α*: nothing corrects a trim error, and it inherits ω_sp ringing.
- **A feedback α-loop with rate damping:** `δ_cmd = K_α·(α_cmd − α) − K_q·q`. More honest (this is what a
  real α autopilot is), more robust, and the `−K_q·q` term is the standard inner rate loop.

**Closed-loop short-period stability under the new δ law is the single thing un-derivable from this plan** —
it is precisely why gate 0 exists. Probe both; pick on evidence; **re-consult the advisor with the numbers**
(the slice-17 gate-0 discipline, which paid).

---

## THE LESSON — the g-limit the airframe imposes on itself

Slices 10/12 taught saturation against `a_max`: an authored number that the engineer picked. Slice 15 taught
the g-*onset* rate cap `k_δ·δ̇_max` — and honestly reported that it did NOT open the miss ("the lack of effect
is the lesson"), because point-mass PN is robust to actuator rate limiting. **Slice 19 is where the airframe
finally bites**, because the cap is no longer a number — it is `Q·S·C_Lα·α_max/m`, and Q is a *flight
condition* that the engagement itself drives.

The showcase contrast: the SAME interceptor, the SAME PN law, the SAME target.
- **`:airframe = point_mass`** — the slice-10 plant: `a_ctrl` applied by fiat, capped at the generous
  authored `a_max`. It pulls what it needs and **HITS**.
- **`:airframe = pitch_coupled`** (with the α autopilot closing δ) — the maneuver accel must be *made* by
  lift. At low dynamic pressure `a_max_aero` falls below the demand, α_cmd pegs at α_max, the missile pulls
  everything it has and it **is not enough** — it **MISSES**.

The live lever is **SPEED** (see finding 3 — not altitude): drag the launch-speed knob up and the miss
closes as Q rises and `a_max_aero` climbs back above the demand. If gate 0 takes the drag-ON variant, the
lesson also becomes *dynamic*: the missile bleeds speed through the engagement, `a_max_aero` decays, and the
g-limit tightens exactly as the endgame demand spikes — the aero cap and the demand cross *during* the shot.

The readout that carries it: **`a_max_aero` vs `a_demand`, on the same axis, both live.** The crossing IS the
verdict — the analog of slice-18's clearance sign.

**Distinguish it, explicitly, from the caps already in the suite** (the copy-paste false-claim trap —
these have been conflated before):

| slice | the cap | what it is |
|---|---|---|
| 10/12 | `a_max` | an authored **magnitude** clamp — a number the engineer chose |
| 15 | `k_δ·δ̇_max` | a **jerk/onset-rate** cap — how fast g can build |
| 15 | `δ_max` | a **deflection** cap — which, through the trim inversion, is an IMPLICIT α ceiling (gate-0 finding: the 4th cap, see the isolation below) |
| **19** | **`a_max_aero = Q·S·C_Lα·α_max/m`** | a **flight-condition** cap — what the air will give you *right now* |

**GATE-0 MEASURED (V0=700, THE PICK):** point-mass **0.276 m** vs coupled **295.168 m** — a **1069×**
separation; `aero_sat` binds **59%** of the guided window; `defl_sat == 0`; `a_max` inert.
**The causal claim, stated as the counterfactual it is (advisor):** *relaxing α_max alone — every other
cap held — recovers **282 of the 295 m***. NOT "the ceiling contributes 282 m additively": gate 0 proved
ceiling and dynamics are **NOT additive** (71 + 12 ≠ 253), so an additive decomposition is a false claim.

**The residual ~13 m** (the caps-relaxed twin) is **"the airframe + autopilot dynamic tracking cost"** —
the irreducible price of steering through a real rotational plant with a finite-bandwidth loop rather
than an instant one. **It is NOT "short-period lag"** (unearned: 6.3× of ω_sp buys only −10%) and **NOT
a projection effect** (measured at −0.081 m — refuted). ω_sp and the loop gains are ENTANGLED; neither
alone dominates. Name it as a §1 approximation of the `:pitch_coupled` plant — it is not a defect, and
the lesson (95.6% of the miss) survives it intact.

---

## The advisor-reconciled design decisions

- **The δ-command seam (the `:a_ctrl` pattern, reused).** The α autopilot's phase-4 `decide!` writes a
  **dynamic scalar δ** into comp (`c[:delta_cmd]`); `_integrate_coupled!` reads
  `get(c, :delta_cmd, get(c, :af_delta, 0.0))` — the commanded δ if the autopilot ran, else slice-17's
  authored trim. **Byte-identity falls out:** a slice-17 open-loop scenario has no Autopilot → no
  `:delta_cmd` key → reads `af_delta` → bit-identical. Same one-tick delay as `:a_ctrl` (phase-4 decide! →
  next tick's phase-1 integrate!), same `haskey`-guard shape, same rationale.
- **THE KNOT — name it, don't paper over it (advisor).** The lesson's contrast needs **two plant behaviors**
  (point_mass: `a_ctrl`/fixed-`a_max`; coupled: δ/aero-limited), which fights convention 9's one-toggled-
  fidelity rule and the single shared client button. **The lean: `:airframe` is the toggled fidelity** —
  `point_mass` keeps the slice-10 path TEXTUALLY UNCHANGED, `pitch_coupled` is the new δ/aero path, and the
  speed knob is the live lever. **How the autopilot rung follows the airframe is a gate-2 wiring choice:**
  - **(i) a new `:autopilot` rung `:alpha`** (`AUTOPILOT_MODES = (:ideal, :pid, :fin, :alpha)`) that is
    *adaptive*: commands `a_ctrl` under `:point_mass`, δ under `:pitch_coupled`. One button
    (`:airframe`), the rung authored once in the scenario. **Preferred** — it keeps the two fidelities
    orthogonal in the way slices 10–15 kept `:guidance`/`:autopilot`/`:seeker` orthogonal.
  - **(ii) the `:airframe` button implies the inner law** (no new rung; `:pitch_coupled` + an Autopilot ⇒ the
    α loop). Fewer moving parts, but it entangles two fidelity keys' meanings.
  Decide at gate 2 with the gate-0 numbers in hand. **Do not inherit the plan-of-record's assumption that
  one button does this cleanly** — it does not, and the plan should say so.
  **ADVISOR-AFFIRMED (post-gate-0): take (i)** — button toggles `:airframe` alone, autopilot authored at
  `:alpha`, satisfying convention 9 (one toggled fidelity). **SPEC THE CROSS-FIDELITY DEPENDENCY
  EXPLICITLY:** `:alpha`'s behaviour DEPENDS on `:airframe` (a_ctrl under `:point_mass`, δ under
  `:pitch_coupled`) — the first such dependency in the suite, so it must be written down, not implied.
  The point_mass reference arm is `:alpha`-in-a_ctrl-mode (≈ `:ideal`); it need only **HIT**, not match
  any existing slice-10 scenario byte-for-byte — **no conflict with byte-identity**, which is about
  EXISTING scenarios (a slice-1..18 scenario never sets `:alpha`).
- **Naming honesty (the `:pitch_coupled`-not-`:sixdof` precedent).** `:alpha` — it is an **α-command**
  autopilot. NOT `:aero` (over-broad), NOT `:sixdof` (still pitch-plane). Carry a named-approximation line.
- **Class 4c** — physics-changing, NO RNG (truth-fed PN, no seeker in the showcase → "draw-count invariance
  VACUOUS"; the 5th 4c in the arc after 14/15/16/17, with slice 18's 4a interrupting). Live-settable, **NO
  `set_fidelity` guard** (the `:integrator`/`:autopilot`/`:apn`/`:cooperation`/`:airframe` precedent;
  CONTRAST slice-13 `:scan`'s introduce-reject). Do **not** re-derive this — advisor confirmed it holds.
- **Crash-safety (convention 5) — the `a_cmd/Q` divide is THE site.** `Q = ½ρV² → 0` at launch/apex ⇒
  `α_cmd = a_perp·m/(Q·S·C_Lα)` → Inf → NaN into `pos` → an invalid state frame, and a throw inside
  `decide!` silently drops the session. **Floor Q** (`Q_FLOOR`, the `_AIRFRAME_V_FLOOR`/`_FRAME_EPS`
  precedent) **AND clamp α_cmd to ±α_max** (which the lesson needs anyway — belt and braces, and the clamp
  is the physics). Also: `C_Lα → 0` is a live slider (`af_cla`, min −5 in slice 17!) — a **zero or negative
  C_Lα divides or flips the sign**. Floor/guard the divisor at the consumer; a live drag through zero MUST
  NOT crash a tick.
- **The isolation, ASSERTED — but STRUCTURALLY (GATE-0 CORRECTION; this reverses the plan's first draft).**
  There are **FOUR caps** here, not three, and the naive slice-15-style `saturated == 0` assertion **FAILS**:

  | cap | value (THE PICK) | status |
  |---|---|---|
  | `a_max` (slice 10) | 3000 | **INERT — PROVEN**: `a_max=3000` ≡ `a_max=1e7` **bit-for-bit** (miss + full trajectory, V0 ∈ {500,700,1000}). It clamps **560×** in the guided window and changes NOTHING. |
  | **`a_max_aero`** | **269.39 @ V0=700** | **THE LESSON** |
  | **`δ_max` (slice-15's DEFLECTION cap — THE 4th)** | 0.4 | an IMPLICIT α ceiling at ≈`(Cmd/\|Cma\|)·δ_max`. **It silently contaminated gate-0's first causation twin.** |
  | `δ̇_max` (slice-15's rate cap) | — | not modeled this slice (named deferral) |

  **Why `saturated == 0` fails and must NOT be copied:** the ceiling-limited missile diverges → the LOS
  rate grows → PN demand escalates to 4856–29935 m/s², genuinely above `a_max`, in the guided window
  (r > 150 m — NOT an endgame artifact). But every one of those clamps is **inert**: `a_max` clamps
  `a_cmd` UPSTREAM of the α inversion, and since `a_max_aero < a_max` the clamped `a_perp` still pegs
  `α_cmd` at ±α_max. **The tighter clamp wins downstream.** Copying slice-15's assertion is the
  convention-4 copy-paste trap — it was correct THERE because its cap sat downstream of `a_max`.
  ⇒ **Assert the STRUCTURAL `max(a_max_aero) < a_max`** (here 550 < 3000, 5.5× margin).
  ⇒ **Assert `defl_sat == 0`** — guaranteed by CONSTRUCTION, not luck: δ_peak is deterministic at
  launch (α=0, α_cmd pegged) at `(|Cma|/Cmd + k_α)·α_max = 0.2667 < δ_max = 0.4` (33% margin).

---

## The three gates (planned)

### 0. Gate-0 probe (throwaway, `M:\claud_projects\temp\slice19_probe\`)

Reuse the REAL core (`using EWSim`: `pn_accel`/`clamp_accel`/`total_accel`/`lift_accel`/`rk4_coupled`/
`pitch_moment`/`trim_alpha`/`short_period_freq`/`_norm3`/`los_*`); hand-roll only the α-autopilot candidate +
the `integrate!`/`decide!` loop. The slice-17 probe (`temp/slice17_probe/`) is the direct template.

**Confirm + pin:**
1. **The δ law** — static trim inversion vs the feedback α-loop with q-damping. **Closed-loop short-period
   stability** under each (the one thing un-settleable from the plan). Pick on evidence; record why.
2. **The SIGN chain, end-to-end** — `a_perp > 0 → α_cmd > 0 → δ > 0 → nose-up moment → α builds → error
   reduces`. A **double flip passes a magnitude-only check** (slice-16 moment / slice-17 lift — **third
   occurrence**). Pin each arrow, not the outcome.
3. **The isolation numbers** — an operating point where `a_max_aero < a_demand < a_max`: the aero limit
   binds, slice-10's clamp does NOT, any fin rate limit does NOT. **Without this the slice has no lesson.**
4. **SEPARATE THE G-LIMIT MISS FROM THE RESPONSE-LAG MISS (advisor — the load-bearing goal).** The isolation
   in (3) proves the ceiling is *binding*; it does **NOT** prove the ceiling *causes* the miss. The coupled
   airframe adds **TWO** things vs slice-10's instant plant: the **g-ceiling** `a_max_aero` (the intended
   lesson) AND the **short-period response lag** (`δ → M → q → θ → α → lift → γ̇` is a multi-stage lag the
   point-mass plant does not have at all). Either could open the miss — and if it is the LAG, this slice has
   relabeled a **slice-15-class effect** (onset/lag) as a new lesson, which is exactly the false-claim class
   conventions 4/11 exist to catch and which the table above claims to have separated.
   **The proof:** a coupled twin with a GENEROUS α_max (ceiling non-binding; SAME ω_sp, speed, geometry,
   approach dynamics) must **HIT**. That — and only that — licenses the causal claim.
5. **The Q lever (finding 3) — and WHY IT CANNOT BE THE CAUSATION PROOF (advisor).** Launch-speed range that
   spans hit↔miss. **But speed is CONFOUNDED:** raising it raises Q, which raises `a_max_aero` **and** the
   short-period frequency `ω_sp = √(−Cmα·Q·S·d/I) ∝ √Q` — it moves the ceiling and the response-speed
   TOGETHER, so closing the miss by adding speed cannot say which one did it. **`af_alpha_max` is the clean
   discriminating knob:** verify in the source that α_max enters **ONLY** the α_cmd clamp — it is absent from
   `pitch_moment`, `lift_accel`, and `short_period_freq` — so it moves the ceiling ALONE. (This is slice-12's
   "raise the limit and PN recovers" test, done cleanly.) Keep speed as the *physical-story* lever for the
   live demo; use α_max for causation.
   **Also:** the drag-ON dynamic variant is the prettier showcase but a WORSE causation testbed (speed, ω_sp
   and the ceiling all vary during the shot). Do the causation proof on the simplest STATIC-speed scenario;
   use drag-bled as showcase only, if at all.
5. **The α_max value** — a physically defensible stall-ish limit (rad) that makes the geometry work.
6. **Byte-identity** — a slice-17 open-loop scenario (no `:delta_cmd`) and a slice-10 point-mass guided
   scenario both bit-identical.
7. **NO RNG** on the path (the 4c claim).
8. **Q→0 / C_Lα→0 / C_Lα<0** degenerates survive a long knob-drag (no NaN, no throw).

Write `FINDINGS.md`; pin the geometry / launch speed / α_max / gains / target maneuver + the miss numbers +
conservative verifier bounds. **RE-CONSULT THE ADVISOR after the numbers** (slice-17 precedent — it paid).
Forward-flag the gate-1/2/3 seams.

### 1. `airframe.jl` primitives green (pure, RNG-free, no LinearAlgebra — §9 house style)

Add:
- `alpha_command(a_cmd::Vec3, vel::Vec3, mass, p::AirframeParams; alpha_max, q_floor) -> (α_cmd, sat::Bool)`
  — the signed projection + the Q-floored divide + the α_max clamp. Returns the saturation flag (the
  telemetry tell). **This one function holds the crash-safety AND the lesson.**
- `aero_accel_limit(V, mass, p::AirframeParams; alpha_max) -> a_max_aero` — `Q·S·C_Lα·α_max/m`, the
  headline readout. Trivially closed-form; it is the *pin*, so it gets its own name (the
  `short_period_freq` precedent).
- the δ law (gate-0's pick), e.g. `alpha_autopilot_delta(α_cmd, α, q, p; ...) -> δ_cmd`.
- `ALPHA_*` mode/limit consts if gate 2 takes wiring (i) — **before `radar.jl`** (convention 1/7).

`pitch_moment`/`rk4_rot`/`airframe_step`/`short_period_freq`/`trim_alpha`/`lift_accel`/`rk4_coupled`
**UNCHANGED** (the byte-identity anchor). **`AirframeParams` should NOT need a new field** — α_max is a
*limit*, not an aero coefficient; carry it in comp (`:af_alpha_max`) and pass it as a kwarg. (If gate 0
forces a field, it goes LAST — the slice-17 `Cla` precedent — and every call site updates in lockstep:
`missile.jl:179`, `:231`, `:281`, plus the tests.)

`test_airframe.jl` teeth (convention 11 — explicit `atol`, external anchors, no self-calibration):
- **The SIGN chain**, each arrow pinned (trap #1).
- **`a_max_aero` closed-form** vs an INDEPENDENT recompute; and the **round-trip**: `α_cmd` at exactly
  `a_max_aero` demand ⇒ `α_cmd == α_max` (the clamp is exactly the limit — the two names agree).
- **The Q floor**: `V → 0` ⇒ finite α_cmd, no NaN, no throw.
- **`C_Lα → 0` and `C_Lα < 0`**: finite, no divide-blowup (the live-slider guard).
- **The α_max clamp binds**: demand above `a_max_aero` ⇒ `sat == true` and `α_cmd == ±α_max` exactly.
- **Steady-state consistency**: a δ from the α-loop at trim reproduces slice-17's `trim_alpha` inverse
  (`atol`-pinned — the two directions of the same balance).

Slices 1–18 byte-identical through the include.

### 2. Wired — the α autopilot rung + the δ seam + loader

- `missile.jl` `decide!` (`:437`): the `:alpha` branch, **fetched INSIDE the branch** (the slice-12/15
  fetch-in-branch bit trap) so the `:ideal`/`:pid`/`:fin` arms stay TEXTUALLY UNCHANGED. It writes
  `c[:delta_cmd]` (and, under `:point_mass` if wiring (i), `c[:a_ctrl]` exactly as today).
- `missile.jl` `_integrate_coupled!` (`:168`): read `get(c, :delta_cmd, get(c, :af_delta, 0.0))` — the ONLY
  change to the coupled path. **`a_ctrl` stays OUT** (finding 1). **Fix the stale `:164` comment.**
- `guidance.jl`: `AUTOPILOT_MODES` gains `:alpha` if wiring (i) (`:49`) — a new RUNG of an existing key (the
  slice-15 `:fin` precedent), so `LIVE_FIDELITY_MODES` (radar.jl:**210**) picks it up with **zero** further
  edits; `_KNOWN_FIDELITY_KEYS` (scenario.jl:**564**), `_validate_fidelity` (scenario.jl:**566**), and
  `set_fidelity` (server.jl:**189**) all derive from that one list (convention 7 — verify nothing re-lists).
  **NO `set_fidelity` guard** (class 4c).
- **`FinState` UNTOUCHED** (finding 2). If gate 0 wants the rate limit in the loop, a **scalar** servo is a
  separate ~10-line kernel — the `fin_autopilot_step` "duplicate, don't share" precedent (`guidance.jl:483`).
  Default: **not this slice** (named deferral).
- Telemetry (phase-4 `decide!`, the slice-17 lift-keys precedent — **gated on the RUNG**, so a slice-1..18
  wire ships NO new key and stays byte-identical; zeroed on the no-target/impacted early-return at `:446`
  so keys never go stale): `alpha_cmd`, `alpha_ach`, `delta_cmd`, `a_max_aero`, `q_dyn`, `aero_sat`. All
  `_finite`-clamped (convention 6). All scalars — **no Arrays** (the client `float()`-crash watch-item).
- `scenario.jl`: parse `airframe.alpha_max` → `:af_alpha_max` (LOAD-validate **> 0** — unlike `cma`/`cla`,
  a limit has no lesson-adjacent negative branch), autopilot gains/`q_floor` similarly. The `airframe:`
  block is otherwise slice-17 verbatim.
- Tests:
  - `test_missile.jl`: a **transient GOLDEN** on the closed-loop coupled path (the slice-17 stage-θ lesson —
    `atol` 1e-6/1e-9; the ONLY thing that catches a subtly-wrong-but-plausible wiring); the **non-dead
    toggle** (`:point_mass` hits, `:pitch_coupled` misses — pinned on miss distance, both directions); the
    **aero-limit binds** (`aero_sat` set, `defl_sat == 0`, structural `a_max_aero < a_max` — **NOT**
    `saturated == 0`); the δ seam (`:delta_cmd` absent ⇒ `af_delta` ⇒ slice-17 bit-identical); loader
    parse/reject. **The `a_max`-INERTNESS test is cheap and decisive: same scenario at `a_max` = 3000 vs
    1e7 ⇒ trajectory `==` bit-for-bit** (gate 0 proved it; pin it so a future edit can't quietly make
    slice-10's clamp load-bearing again).
  - `test_determinism.jl` (the 14/15/16/17 **4c shape**, NOT the 11/13 RNG shape): same-seed bit-identical
    with **NO RNG** on the path (pin `t` AND a per-missile pos sequence); a slice-1..18 scenario
    byte-identical; the `:point_mass ↔ :pitch_coupled` toggle CHANGES the trajectory with no RNG;
    introduce-safe BOTH directions.
  - `test_server.jl`: `set_fidelity` write/reject/introduce both ways; a live `speed`/`af_alpha_max`/`af_cla`
    slider → tick survives (**"a live knob can never crash a tick"** — drag `af_cla` through **0 and
    negative**, the divisor guard).
  - Slices 1–18 byte-identical (`test_determinism` + the `_sample_z` absolute golden green).

### 3. Scenario + Godot view + four proofs (convention 14)

- `scenarios/slice19_alpha_limit.yaml` (seed 19): **PLANAR** (all y = 0 — the out-of-plane approximation
  CONSTRAINS the geometry). One coupled+guided interceptor (`[BallisticMissile]` + `[Autopilot]` — **the
  FIRST coupled AND guided missile in the project**; slice 17 was open-loop with no target) vs a target whose
  maneuver demands more than the low-Q airframe can give. `fidelity: {airframe: pitch_coupled, guidance: pn,
  autopilot: alpha}` — **one TOGGLED fidelity** (`:airframe`; the others authored-and-fixed — convention 9).
  Knobs: **launch speed** (THE Q lever), `af_alpha_max`, `af_cla`. Numbers probed FIRST, then pinned against
  the live `load_scenario → tick! → telemetry` wire (convention 10 — NOT a hand-recompute).
- **Godot**: the airframe view carries over from slice 17 wholesale — `_fid_kind = "airframe"`, the curved
  trail, the nose/velocity/α drawing (all `_airframe_view` gated; the slice-17 site-audit found reuse is
  lowest-risk). The cycler already shows on `_fidelity.has("airframe")` (the slice-17 value-guard) → **it
  works unchanged**. The NEW visual: **`a_max_aero` vs `a_demand`** as the headline readout (the crossing
  is the verdict), plus an `aero_sat` tell. **Watch-item:** `_setup_spatial_fid_btn` checks the airframe
  branch FIRST (the slice-16→17→18 value-guard chain) — verify slice 16 STILL drops the button and slice 18's
  terrain branch is untouched.
- `net/slice19_verify.gd` (drives the real server). **EVERY assertion is on FRAME-SAMPLED values —
  sub-metre is UNREACHABLE on the wire (GATE-0 CORRECTION, blocking):** closing speed at CPA ≈ **1373
  m/s** and `emit_every=16` ⇒ frames ≈ **22 m apart** near CPA, so a TRUE 0.276 m point-mass CPA is
  frame-sampled as up to **15.2 m**. The plan's first-draft `pm HITS < 1 m` would FAIL *on a hit* — the
  exact coarseness [[ewsim-missile-verifier-sampling]] warns of. **Assert the RATIO/SEPARATION:**
  - `pm_frame < 30` AND `coupled_frame > 250` AND **`ratio > 8×`** (gate-0 measured 33–145× across
    V0 ∈ [400,1000]; worst 33.3× ⇒ 4× margin). The coupled side samples faithfully (295.186 vs
    295.168 true) — only the HIT side is coarse.
  - **the isolation**: `aero_sat` set, **`defl_sat == 0`**, and the **structural `a_max_aero < a_max`**
    (**NOT** `saturated == 0` — it FAILS; `a_max` clamps 560× INERTLY, see the isolation section).
  - **THE CAUSATION PROOF — the `af_alpha_max` sweep**: raise α_max via `set_param` with **speed HELD**
    and the miss closes to **< 20 m** ⇒ the ceiling caused it. Gate-0 confirmed this sweep is clean at
    the **AUTHORED δ_max = 0.4** (identical to the δ_max=50 sweep to every digit, `defl_sat == 0`
    throughout) ⇒ **no `set_param(delta_max)` escape hatch needed**. (α_max moves the ceiling ALONE;
    speed moves ceiling AND ω_sp together, so speed is the *demo* lever, **NOT** the causation proof.)
  - held-seed **replay bit-identical** (RNG-free); `set_fidelity airframe point_mass` ACCEPTED live (4c).
  **Re-pin every number against the live wire first** (convention 10) — 295.168 is a PROBE number; the
  real `decide!`/`integrate!` ordering may shift it. Do NOT hard-code 295 before the wire confirms it.
  `S19V OK`, exit 0. Drain in multiples of `emit_every`; **[[ewsim-missile-verifier-sampling]] applies** —
  exclude post-CPA re-crossings AND the r→0 endgame spike; make the target outrun the missile for a clean
  first CPA.
- `net/slice19_ui_test.gd` (mock client, no server): the cycler wraps `:point_mass↔:pitch_coupled` →
  `set_fidelity`; the speed/α_max sliders → `set_param`; a slice-16 handshake STILL drops the button; a
  slice-18 terrain handshake still takes the 3-D branch (**the value-guard, all three ways**). `S19UI OK`.
- `Sandbox.tscn` **headless smoke-load** against the slice-19 server (`DONE` ⇒ scene connected, no parse
  bugs); re-smoke-load slices 16/17/18.
- `test_scenario.jl` loader testset (parses the real yaml; `af_alpha_max`/speed at consumed keys + knobs;
  rejects `alpha_max ≤ 0`).
- The **windowed shot** ([[ewsim-godot-headless]]): the coupled interceptor pegged at α_max, curving as hard
  as the air allows and **sliding past the target** — vs the point-mass twin's clean intercept. The α gap
  visibly SATURATED (nose pegged off the velocity vector) is the picture of this slice.

---

## Deferred (NAMED)

- **An exponential atmosphere `ρ(z) = ρ₀·exp(−z/H)`** (finding 3) — makes "high altitude" a REAL Q lever,
  and is the honest completion of this lesson. Touches the shared drag path + `:rho`'s meaning ⇒ its own
  slice. **Until it exists, say "low dynamic pressure (slow)", never "high altitude."**
- **The rate-limited fin INSIDE the coupled loop** — a scalar servo (NOT the Vec3 `FinState`, finding 2)
  feeding `Cmδ·δ`. This is where slice-15's banked δ finally pays off dramatically: the **guidance limit
  cycle** that slice 15 predicted would "genuinely need the deferred 6-DOF". A real slice-20 candidate.
- **Induced drag** (`C_Di ∝ C_L²` — lift costs speed). Currently lift is drag-free/speed-preserving
  (`lift_accel` is ⟂ v). It COMPOSES with this lesson viciously: pulling g bleeds V, which lowers Q, which
  lowers `a_max_aero`, which... — a genuine feedback spiral. Named-deferred since slice 17.
- **Nonlinear `C_L(α)` / true stall** — α_max here is a hard clamp, a named approximation standing in for
  the lift-curve rolling over. The clamp is honest; the curve is the next rung.
- **Bank-to-turn / 3-D** (quaternion + ω — the geometry→frames "2-D first" precedent) — the out-of-plane
  discard (scope) disappears only here. Then the **radome/body-rate parasitic loop** (needs body rates + a
  body-mounted seeker — the slice-11 Seeker + this slice's rotation, finally composed).
- **A seeker in the coupled loop** — slice 19 is truth-fed (the 4c "no RNG" claim). Adding the slice-11
  Seeker flips the class back to 4a/RNG-live (conventions 3/11 re-apply — the slice-13 precedent).
- Per-channel fin allocation / hinge moment; a 2nd-order actuator (ω_a/ζ_a).

---

## Watch-items (gotchas to bake in)

- **`:a_ctrl` MUST STAY OUT of the coupled force (finding 1, load-bearing).** Adding it rebuilds the
  point-mass plant and silently deletes the lesson — the aero ceiling never binds. The slice-17 comment at
  `missile.jl:164` says to add it. **It is wrong. Fix it.**
- **THE SIGN CHAIN IS THE #1 TRAP — third occurrence in this arc.** Slice 16 caught it on the moment sign,
  slice 17 on the lift direction; slice 19 has a LONGER chain (`a_perp → α_cmd → δ → M → α → lift → γ̇`) and
  therefore more places for an even number of flips to hide. **A double flip passes a magnitude-only test.**
  Pin each arrow individually (the slice-16 tooth-#1 discipline).
- **THE `a_cmd/Q` DIVIDE IS THE CRASH-SAFETY SITE (convention 5).** Q→0 at launch/apex; `C_Lα→0`/`<0` is a
  LIVE slider (slice-17's `af_cla` min is **−5**). Floor the divisor AND clamp α_cmd. A throw in `decide!`
  lands in the session's IO-only catch and **silently drops the connection**.
- **THE ISOLATION IS STRUCTURAL, NOT `saturated == 0` (GATE-0 CORRECTION — the plan's first draft was
  WRONG).** Assert `max(a_max_aero) < a_max` + `defl_sat == 0`. `saturated == 0` **FAILS**: `a_max`
  clamps 560× in the guided window, INERTLY (proven bit-for-bit at `a_max` = 3000 vs 1e7). Copying
  slice-15's assertion across is itself the convention-4 copy-paste trap. See the isolation table.
- **THERE IS A FOURTH CAP — `δ_max` — AND IT WILL CONTAMINATE THE CAUSATION TWIN IF YOU LET IT.** Through
  the trim inversion, δ_max is an IMPLICIT α ceiling at ≈`(Cmd/|Cma|)·δ_max`. Gate 0's first "generous
  α_max=1.5" twin never got near 1.5 (α_peak 0.52) — δ_max=0.5 capped it, and ~4 of the "12 m lag floor"
  was δ_max. **Relax α_max AND δ_max together in the twin.** Relaxing the cap under test while leaving
  another binding is the false-claim trap one level down — it fooled gate 0 for two probes.
- **BINDING ≠ CAUSING (advisor, load-bearing) — RESOLVED at gate 0, keep the discipline.** The isolation
  proves the ceiling BINDS, not that it CAUSES the miss; the coupled plant also carries a dynamic
  tracking cost the point-mass plant lacks (a slice-15-class concern). **The discriminator is
  `af_alpha_max`, which enters ONLY the α_cmd clamp** (absent from `pitch_moment`, `lift_accel`,
  `short_period_freq`) — it moves the ceiling with ω_sp/Q/geometry FIXED. **Speed is CONFOUNDED**
  (`ω_sp ∝ √Q` moves ceiling AND response-speed together) ⇒ demo lever only, never the causation proof.
  Gate-0 measured: relaxing α_max alone recovers **282 of 295 m (95.6%)**, residual **13 m**.
- **STATE THE LESSON AS A COUNTERFACTUAL, NOT A DECOMPOSITION (advisor).** "Relaxing α_max alone recovers
  282 of 295 m" — NOT "the ceiling contributes 282 m". Gate 0 proved ceiling and dynamics are **not
  additive** (71 + 12 ≠ 253), so "owns/contributes" implies a decomposition that does not hold.
- **DO NOT CALL THE ~13 m RESIDUAL "SHORT-PERIOD LAG"** — the label is UNEARNED (6.3× of ω_sp buys −10%;
  it floors at ~12.2, not at the point-mass 0.276). Nor is it the ⟂-v-vs-⟂-LOS projection (measured at
  −0.081 m — **refuted**, though the along-v̂ component of a_cmd does reach 0.55·|a_cmd|). ω_sp and the
  loop gains are ENTANGLED; neither alone dominates. Call it **"the airframe + autopilot dynamic tracking
  cost"** and name it as a §1 approximation.
- **`k_α`/`k_q` ARE AUTHORED CONSTANTS — NEVER KNOBS.** The α_max clamp bounds the COMMAND; lift uses the
  ACHIEVED α. A hot loop (k_α=100) lets achieved α overshoot α_max ⇒ transient lift ABOVE `a_max_aero`
  ⇒ **the ceiling LEAKS** (gate 0: miss collapses 295 → 62.8 m, fin bang-bang at defl_sat=4012). At the
  authored gains this is moot (α_peak = 0.1369 never even reaches the 0.2 clamp — it is demand-limited),
  but an exposed gain slider is a live path to eroding the lesson. A true stall would bound the ACHIEVED
  α — that is the nonlinear `C_L(α)` deferral.
- **"HIGH ALTITUDE" IS FALSE HERE (finding 3).** ρ is constant. Only V moves Q. Three prior plans say
  otherwise; do not propagate it further, and fix the phrasing in STATUS/HANDOFF at gate 3.
- **THE "HALVES JOIN" PHRASING IS OVERSOLD (finding 2).** `FinState.δ::Vec3` vs `pitch_moment(delta::Float64)`
  — different frames. Scalar δ through `af_delta`; `FinState` untouched. Write the honest comment.
- **CLASS 4c, live-settable, NO guard, NO RNG** — the 14/15/16/17 precedent (slice 18's 4a was the
  interruption). "Draw-count invariance" is **VACUOUS** — do NOT copy slice-11/13 draw language (convention
  4's copy-paste false-claim trap). Advisor confirmed; don't re-derive.
- **THE OUT-OF-PLANE DISCARD CONSTRAINS THE SCENARIO.** A pitch-plane α autopilot cannot make y-accel. The
  engagement must be planar; a target maneuvering out of plane would be UNFLYABLE by construction (and would
  look like a bug). State it as a §1 named approximation in the scenario header.
- **THE STAGE-θ BUG CLASS HAS NO HOME HERE (advisor) — ship the golden anyway, but do not hunt.** δ is
  computed ONCE per tick in `decide!` and held CONSTANT across the next step's four RK4 stages: it is an
  EXTERNAL input, not stage-varying state, so slice-17's entry-θ-vs-stage-θ hazard cannot recur for the
  autopilot. (The lift/moment stage-θ read inside `_integrate_coupled!` is slice-17 code and stays as-is.)
  Ship a transient golden as cheap insurance against a plausible-but-wrong wiring — just don't burn gate-2
  effort looking for a stage-θ bug that has nowhere to live.
- **Verifier sampling** — [[ewsim-missile-verifier-sampling]]: first-descending-band CPA, exclude the r→0
  endgame spike, pin the RATIO not the frame-sampled min, target outruns missile.
- **The client value-guard is now THREE-way** (16 drops / 17-19 show / 18 terrain-3D). `_setup_spatial_fid_btn`
  checks airframe FIRST. Re-run every prior UI test + smoke-load.

---

## Context / landmarks

- **The primitives slice 19 extends:** `core/src/airframe.jl` — `AirframeParams`(:46, `Cla` LAST at :54),
  `_AIRFRAME_V_FLOOR`(:61, the floor precedent), `pitch_moment`(:78, the δ consumer — **scalar**),
  `rk4_rot`(:97), `airframe_step`(:117), `short_period_freq`(:131), `trim_alpha`(:152, **the inverse the δ
  law computes**), `lift_accel`(:181, the perp direction `α_cmd` projects onto), `rk4_coupled`(:207),
  `AIRFRAME_MODES`(:224). NEW: `alpha_command`, `aero_accel_limit`, the δ law.
- **The loop slice 19 closes:** `missile.jl` — `BallisticMissile.integrate!`(:84), the **`a_ctrl` guard**(:115,
  the point-mass path — the seam pattern to copy, **not** the force to add), **`_integrate_coupled!`**(:168,
  the δ read + the stale comment at :164), `_integrate_airframe!`(:224), `build_env!`(:249),
  `_airframe_view_info`(:320, the handshake marker — REUSED unchanged), `Autopilot`(:416),
  `Autopilot.integrate!`(:425, the dt capture), **`Autopilot.decide!`(:437** — the α branch lands here;
  no-target zeroing at :446, `a_max` at :485, the outer-law `a_dem` at :530, `clamp_accel` at :546, the
  **slice-15 `:fin` branch at :559** = the branch-shape template, `c[:a_ctrl]` at :588).
- **The force model:** `core/src/dynamics.jl` — `gravity_accel`(:46), `drag_accel`(:61), `total_accel`(:75),
  `integrator_step`(:125). ρ is a **constant** here (finding 3).
- **The autopilot kernels:** `core/src/guidance.jl` — `AUTOPILOT_MODES`(:49), `GUIDANCE_MODES`(:70),
  `AutopilotState`(:99, **structurally FROZEN** — slice-15 advisor #4), `FinState`(:118, **Vec3 — NOT
  reused**), `clamp_accel`(:384), `autopilot_step`(:432), `fin_autopilot_step`(:498, the
  "duplicate-don't-share" precedent).
- **Fidelity plumbing (verified 2026-07-17 — the slice-17 plan's numbers are STALE):**
  `LIVE_FIDELITY_MODES` = **radar.jl:210**; `_KNOWN_FIDELITY_KEYS` = **scenario.jl:564**;
  `_validate_fidelity` = **scenario.jl:566**; `set_fidelity` = **server.jl:189**. One-list-no-drift
  (convention 7) — a new RUNG of `AUTOPILOT_MODES` needs **zero** plumbing edits.
- **The class-4c precedent** (physics-changing, no RNG, live-settable, NO introduce-reject): `:integrator`
  (8), `:autopilot`(9/15), `:apn`(12), `:cooperation`(14), `:airframe`(17). CONTRAST slice-13 `:scan` (4b,
  introduce-rejected) and slice-18 `:terrain` (4a).
- **The slice-17 probe as the template:** `M:\claud_projects\temp\slice17_probe\` (`probe.jl`,
  `scenprobe.jl`, `FINDINGS.md`).
- **HANDOFF** §11 Tier-A (the 6-DOF entry — 15 = fin, 16 = rotation, 17 = coupling, **19 = the closed inner
  loop**), §2 (the cascade), §3 (the tick contract), §1 (named approximations).
- **Memory:** [[ewsim-fin-dynamics-direction]] (the 6-DOF arc tracker — **update on completion**),
  [[ewsim-missile-verifier-sampling]] (the CPA sampling teeth — directly applies), [[ewsim-godot-headless]]
  (the shot harness), [[ewsim-realtime-dt-floor]] (keep dt = 1e-3).

---

## Task checklist

- [x] **0. Probe + config pin** — **DONE** (`M:\claud_projects\temp\slice19_probe\`: `probe.jl`…`probe8.jl`
      + `FINDINGS.md`; advisor re-consulted, 2 blockers + 5 soft items folded in above). **THE PICK:**
      geometry = slice-12 base (m1 (0,0,3000) elev 12°, target (6000,0,4200) vel (−800,0,200), `a_lat`=200);
      mass 140, S=π·0.1², d=0.2, **I=20, Cma=−1.0, Cmd=+3.0, Cmq=−150, Cla=20**; **k_α=1.0, k_q=0.3**
      (AUTHORED, never knobs); **α_max=0.2, δ_max=0.4, a_max=3000** (inert), V0=700 (knob 400–1200),
      **drag OFF**, dt=1e-3. **CONFIRMED:** δ law = **`:ff_fb`** (FF trim inversion + feedback — err ~1e-12,
      ~0% overshoot; `:static` rings 72–96%, `:fb` has the exact 5/6 = slice-9 `1/(1+Kp)` undershoot);
      closed-loop STABLE across ω_sp ∈ [9.7, 68.7]; the **7-arrow sign chain + mirror** OK; the
      `a_max_aero ↔ α_max` round-trip exact (2.8e-17); **point-mass 0.276 m vs coupled 295.168 m (1069×)**;
      **causation: relaxing α_max alone recovers 282 of 295 m (95.6%)**, residual 13.1 m; `aero_sat` 59% of
      the guided window, `defl_sat`=0, `a_max` INERT (3000 ≡ 1e7 bit-for-bit); all degenerates finite
      (V→0, C_Lα ≤ 0, Cmδ→0, Cma=+0.5 unstable closed loop 14 s); A-vs-B bit-identical, NO RNG (4c).
      **FIVE PLAN CORRECTIONS FOLDED IN:** (1) the isolation is STRUCTURAL, `saturated == 0` FAILS;
      (2) a FOURTH cap `δ_max` contaminated the first causation twin; (3) the residual is NOT
      "short-period lag" nor a projection effect; (4) the verifier CANNOT assert sub-metre (frame
      sampling) — assert the ratio; (5) `k_α`/`k_q` must not be knobs (the ceiling leaks via achieved-α
      overshoot). Drag-bled DEFERRED (works — miss 295→417 — but confounds intra-run).
- [x] **1. Primitive** — **DONE (2604 → 2720 tests, +116; slices 1–18 byte-identical).** `airframe.jl`
      gains `aero_accel_limit`, `alpha_command`, `alpha_autopilot_delta` (+ `_AIRFRAME_Q_FLOOR`=1e-3 /
      `_AIRFRAME_DENOM_FLOOR`=1e-9, the `_AIRFRAME_V_FLOOR` precedent), appended AFTER `AIRFRAME_MODES`;
      3 exports in `EWSim.jl`. **NO `AirframeParams` field** (α_max/gains are LIMITS → comp/kwargs) and
      **NO mode const here** — `:alpha` is a gate-2 edit to `AUTOPILOT_MODES` in `guidance.jl`. Every
      slice-16/17 primitive TEXTUALLY UNCHANGED ⇒ byte-identity is structural (the `_sample_z` golden +
      `test_determinism` green prove it). **THREE ADVISOR CALLS FOLDED IN (all pre-write):**
      (1) **do NOT floor `aero_accel_limit`** — it has no division, is finite on its own, and the true
      ceiling at V→0 genuinely IS zero; flooring the READOUT would be a hidden §1 approximation. The
      floor belongs only at the two divide sites (`alpha_command`'s Q, `alpha_autopilot_delta`'s Cmδ).
      Command (safety-floored) and readout (pure formula) stay decoupled; at operating V they agree
      exactly anyway. (2) **round-trip is `atol=1e-15`, NOT `==`** (α_raw lands ~1 ULP below α_max ⇒ the
      clamp never engages — gate-0's 2.8e-17). (3) **ship ONLY `:ff_fb`** — no `law::Symbol` selector, no
      dead `:static`/`:fb` branches. Returns `(δ, defl_sat::Bool)`.
      **`test_airframe.jl` — 7 new testsets (110 asserts):** the **7-arrow sign chain + mirror +
      antisymmetry** (each arrow pinned individually — the #1 trap's 3rd occurrence); `a_max_aero`
      independent recompute + V²/α_max scaling + the **exact round-trip** (`α_cmd ≈ α_max` at a demand
      of exactly `a_max_aero` ⇒ `sat ⟺ |a_perp| > a_max_aero`, the two names agree BY CONSTRUCTION);
      **the clamp binds BOTH sides** (advisor: the below-ceiling arm is what fails a stuck-true `sat`);
      the **out-of-plane discard** pinned as the §1 approximation (a huge y-demand changes NOTHING;
      γ-invariance catches a frame slip); the **crash-safety degenerates** (V→0, C_Lα=0 ⇒ `(0.0,true)`,
      **C_Lα<0 self-consistent** — α_cmd flips, lift still lands on +n̂ at the commanded 100.0 m/s²:
      the tooth that catches a stray `abs` in the command; a 24-case finite sweep); **trim consistency
      vs slice-16's independently-written `trim_alpha`** (the external anchor — the δ law's steady state
      round-trips, and `pitch_moment(α_cmd, δ_ss) ≈ 0` = the definition of trim); the **closed-loop α
      step** (T=6 s / `atol=1e-12` — **PROBED, not guessed**: the shipped k_α=1 is SLOWER than gate-0's
      k_α=5, so the residual is 1.8e-9 at 4 s but 1.9e-13 by 6 s [floor 2.9e-15 by 8 s] — the plan's
      "err ~1e-12" did NOT transfer across gains) **+ the `:fb` contrast arm** proving the feedforward is
      LOAD-BEARING: feedback-only settles at the hand-derived `Cmδ·k_α/(Cmδ·k_α−Cmα)` = **3/4 = −25%**
      at the SHIPPED gains (gate-0's 5/6/−16.67% was at ITS probe gains — the docstring now names both),
      a 0.0375-rad gap that the two arms separate by 10 orders of magnitude.
      **THE GATE-0 BRIDGE (`temp/slice19_probe/bridge.jl`, advisor):** gate 0's numbers came from
      hand-rolled probe locals; this reruns THE PICK engagement through the **EXPORTED** primitives and
      reproduces gate 0 EXACTLY — miss **295.167860288** (Δ=1.6e-10 = the reference's own rounding),
      aero_sat **2444/4130 = 59%**, `defl_sat` **0**, α_peak **0.1369**, δ_peak **0.2667**, a_max_aero
      **269.39** (< a_max=3000 ⇒ the structural isolation holds), `a_max` 3000 ≡ 1e7 **bit-identical**,
      and the α_max causation sweep at the authored δ_max=0.4 identical to every digit. **Why it matters
      at gate 3:** when the live wire differs from 295.168 (the ordering shift the plan warns of),
      "shipped primitive ≠ probe" is ALREADY RULED OUT — a 2-way diagnosis, not a 3-way one.
      **BYTE-IDENTITY IS STRUCTURAL HERE, NOT TESTED (advisor — do NOT carry the phrasing into gate 2):**
      gate 1 appended new symbols and touched ZERO existing execution paths, so nothing that runs could
      have changed; the green suite proved "no name collision / no load error", NOT "trajectories
      unchanged" (a golden cannot prove a negative about code nothing calls yet). At **gate 2** —
      editing `decide!` and `_integrate_coupled!` — `test_determinism` + the `_sample_z` absolute golden
      become the ACTUAL proof, and the fetch-INSIDE-the-`:alpha`-branch discipline is what keeps
      `:ideal`/`:pid`/`:fin` textually identical.
- [ ] **2. Wired** — the `:alpha` `decide!` branch (fetch-in-branch); the `:delta_cmd` seam in
      `_integrate_coupled!` (**`a_ctrl` stays out; fix the :164 comment**); `AUTOPILOT_MODES` gains `:alpha`
      (zero plumbing edits — verify); rung-gated telemetry (`a_max_aero`/`alpha_cmd`/`aero_sat`/…);
      loader `alpha_max > 0`. Arms: the **transient golden**, the non-dead toggle, the isolation,
      determinism (4c shape), server live-knob survival (drag `af_cla` through 0/negative).
- [ ] **3. Scenario + Godot + verifiers** — `scenarios/slice19_alpha_limit.yaml` (PLANAR, the first
      coupled+guided missile, speed as THE demo knob + α_max as THE causation knob); the slice-17 airframe
      view + the `a_max_aero` vs `a_demand` readout; **four proofs** (`slice19_verify.gd` — coupled MISSES /
      point_mass HITS + the isolation asserted + **the α_max causation sweep (speed held)** + bit-identical
      replay; `slice19_ui_test.gd` — the three-way
      value-guard; the smoke-load; the windowed shot of a saturated α sliding past the target);
      `test_scenario.jl` loader arm. Update `STATUS.md` + `CLAUDE.md` + HANDOFF §11 +
      [[ewsim-fin-dynamics-direction]] — **and fix the "high-altitude" phrasing (finding 3).**
