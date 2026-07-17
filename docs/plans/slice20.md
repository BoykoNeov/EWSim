# Slice 20 — the rate-limited fin INSIDE the coupled loop (§11 Tier-A)

> **The slice-20 slot was REFILLED by a different lesson: see `slice20_induced_drag.md`**
> (induced drag — the g-bleeds-V-lowers-Q spiral, a named deferral of slices 17/19). This file
> remains the record of the DEAD fin candidate. Its probes (`M:\claud_projects\temp\slice20_probe\`)
> are likewise untouched; induced drag probes under `slice20_drag_probe\`.

> ## ⛔ GATE-0 VERDICT: **THIS SLICE IS DEAD. DO NOT BUILD IT.**
>
> **Gate 0 ran (4 probes, `M:\claud_projects\temp\slice20_probe\`) and killed every candidate —
> including two the plan pre-named and one the probe invented. There is NO clean window.** The
> plan below is preserved as the record; the FINDINGS section is the deliverable.
>
> **The structural reason (FINDING 7): `δ_max` SHADOWS `δ̇_max` on this plant.** For the rate cap
> to bind, the fin must need to move fast; it needs to move fast only when the command moves fast
> (high `k_α` or low damping); **both of those drive `δ_cmd` past `δ_max` first.** The deflection
> cap always saturates before the rate cap can be the binding constraint — so cap #5 cannot be
> ISOLATED from cap #3 on this airframe, at any parameter setting probed. The two caps are not
> independent.
>
> Gate 0 did its job: it killed a slice in ~4 probes instead of after a 3-gate build. This is the
> convention-10 "probe empirically, THEN pin" discipline paying for itself.



Slice 15 banked a fin state `δ` and shipped an **admission** as its headline: the rate limit
did NOT open the miss, because point-mass PN is robust to actuator rate limiting — and that
was precisely WHY the dramatic failure modes (guidance limit cycle, α-limited maneuverability,
radome/body-rate parasitics) "genuinely need the DEFERRED 6-DOF". Slices 16/17/19 built that
6-DOF in the pitch plane and CLOSED the inner loop. **Slice 20 cashes the check**: the same
knob that was inert in slice 15 goes back in, now inside a plant that can actually ring.

The pedagogical arc is the point — *one knob, inert then lethal, and the difference IS the
airframe.*

---

## Read these FIRST — three things found while planning

### 1. THE `delta_rate_max` COLLISION IS REAL (load-bearing, advisor-flagged)

`comp[:delta_rate_max]` **already exists** and is set **UNCONDITIONALLY** for every missile
carrying a guidance block (`scenario.jl:443`, default **2.0**, load-validated `> 0`). It is
slice 15's lesson slider, consumed by `fin_autopilot_step` (`guidance.jl:521`).

⇒ **Slice 20 MUST NOT read `:delta_rate_max`.** If the coupled servo gated on that key, every
existing slice-19 scenario would silently grow a servo (the key is always there) and **slices
16/17/19 would stop being byte-identical — convention 2 DEAD.**

**The fix — a NEW, PRESENCE-GATED airframe-block key:**

```yaml
airframe: { ..., delta_rate_max: 8.0 }   # → comp[:af_delta_rate_max]
```

set **only when authored** — `if haskey(ab, "delta_rate_max")` — the **`alt_hold_m` precedent**
(`scenario.jl:120`, slice 18), NOT the airframe-block-presence pattern the other `af_*` keys
use. Gating on the block would re-break byte-identity (slices 16/17/19 all HAVE airframe
blocks); gating on the KEY means only a slice-20 YAML grows it.

This is not merely a naming dodge — the two fins live in different blocks because they are
different plants (see 2).

### 2. TWO `δ̇_max` CAPS NOW EXIST — DIFFERENT PLANTS, DIFFERENT PHYSICS (convention 4)

The copy-paste false-claim trap is sharper here than in any prior slice, because the symbol is
*literally the same*. The suite will carry **five** distinct caps:

| # | Cap | Slice | Plant | What it bounds |
|---|-----|-------|-------|----------------|
| 1 | `a_max` | 10/12 | any | an authored MAGNITUDE clamp |
| 2 | `k_δ·δ̇_max` | 15 | point-mass, Vec3 fin, `a = k_δ·δ` | a **g-onset rate** (jerk) |
| 3 | `δ_max` | 15/19 | both | a DEFLECTION cap |
| 4 | `a_max_aero = Q·S·C_Lα·α_max/m` | 19 | coupled | a **FLIGHT-CONDITION** cap |
| 5 | **`af δ̇_max`** | **20** | **coupled, scalar fin, δ→moment→α→lift** | **an α-onset rate — one loop deeper than #2** |

#2 and #5 are the same symbol in different frames. #2 maps deflection DIRECTLY to accel
(`a = k_δ·δ`, a Vec3 in the accel frame) so its rate cap lands straight on jerk. #5 feeds
`pitch_moment` (a scalar in rad), so it bounds **q̇ → q → θ → α → lift** — the cap arrives at
the acceleration through four integrations, which is exactly why it can destabilize a loop that
#2 could only slow down. **Do not describe #5 in #2's language.**

### 3. THE HEADLINE IS *NOT* COMMITTED — GATE 0 DECIDES IT (advisor, blocking)

`k_α`/`k_q` are **frozen constants and must never be knobs** (slice-19 gate-0 FINDING 14 — a hot
loop leaks lift above the ceiling and erodes the slice-19 lesson). So **`δ̇_max` is the only
lever**, and the shipped `k_α = 1` is a *gentle* inner loop. Rate-saturation limit cycles (PIO)
need enough loop-gain × phase-lag to cross into instability. At a gentle loop the honest outcome
may be **lag, not oscillation** — which is the exact shape of slice 15's predicted-but-absent
"saturation opens the miss".

**This plan therefore names TWO candidate lessons and lets the probe pick.** Writing "limit
cycle" into the scenario/telemetry/docs before gate 0 produces one would repeat slice 15's error
one level up.

---

## GATE-0 FINDINGS (4 probes — THE RECORD; read before ever re-proposing this slice)

Probes at `M:\claud_projects\temp\slice20_probe\` (`probe.jl`…`probe4.jl`). All drive the
**SHIPPED** primitives (`alpha_command` / `alpha_autopilot_delta` / `pitch_moment` /
`lift_accel` / `rk4_coupled` / `pn_accel`, convention 10) on the slice-19 engagement with the
pure slew limiter (design 0) inserted. Airframe: `Cmα=-1, Cmδ=3, Cmq=-150, I=20, Cla=20`,
`ω_sp = 9.71 rad/s`.

**FINDING 1 — design 0 VALIDATED.** `δ̇_max = ∞` (passthrough) reproduces slice 19:
**miss 294.879 m** vs the shipped **295.168 m**. The ~0.3 m is probe-vs-wire sampling (the probe
samples every tick, the wire every 16). The pure slew limiter's passthrough claim is sound.

**FINDING 2 — SLICE 19's LESSON *STARVES* SLICE 20's.** At the shipped `α_max = 0.2` the α
command is **PEGGED at α_max for 62.4%** of the run (slice 19 states 59% — same thing, different
sampling). **A pegged command is a CONSTANT command, and a slew-rate limit costs nothing when
tracking a constant** — the fin slews once to the α_max trim and holds. The α loop is
DEMAND-limited, not RATE-limited. This alone makes slice 19's scenario unusable for slice 20.
Unpegging (`α_max ≥ 0.8` ⇒ peg_frac 8%) makes the missile HIT (~29 m = `r_stop`).

**FINDING 3 — THE PLANT IS MASSIVELY OVERDAMPED, AND THE FIN FEEDBACK IS WHY.**
`ζ_aero = 0.104` (Cmq alone) but `ζ_kq = 4.37` at the shipped `k_q = 0.3` ⇒ **ζ_total ≈ 4.47,
with the k_q fin feedback supplying ~98% of the damping.** A slew limiter on a *gentle
proportional* loop (`k_α = 1`) around a *massively overdamped* plant makes it SLUGGISH, not
unstable. **PIO needs loop gain AND rate saturation; this loop has neither the gain nor the
phase margin deficit.** (Candidates A and B die here: the miss is inert 294.9→272.5 across
δ̇ ∈ [∞, 0.1], and it moves the WRONG WAY — tightening the limit *helps* by ~22 m.)

**FINDING 4 — CANDIDATE C (the k_α bandwidth ceiling) IS REAL BUT STRUCTURALLY CONFOUNDED.**
The interaction is dramatic — at `k_α = 30`, an ideal fin (δ̇=∞) **HITS (29.7 m)** while the SAME
autopilot on a rate-limited fin (δ̇=5) **MISSES BY 298 m**. But `defl_sat` binds **4680 of ~4900
steps (95%)**: it is a **bang-bang δ_max-saturated fin wearing a rate-limit costume** — the
convention-4 false-claim trap, 4th occurrence in this arc. The kill is STRUCTURAL, not tunable:
`δ_peak ≈ (|Cmα|/Cmδ + k_α)·α_max ≈ 45 rad` at those gains vs `δ_max = 0.4`. **A hot k_α ALWAYS
pegs deflection.** (Realism corroborates: with δ_max = 0.4 rad ≈ 23° — physical — a well-tuned
k_α is ≈ 2, i.e. exactly the regime where the rate limit is inert. `k_α = 30` is not a "hot"
autopilot, it is an unrealistic one.)

**FINDING 5 — THE MONOTONICITY REVERSAL RECURS ([[ewsim-df-ellipse-sigma-monotonicity]]).** The
miss is **NON-MONOTONE in δ̇_max**: at k_α=30 it runs 30.0 → 128.5 → **298.0 (peak at δ̇≈5)** →
123.0 → **29.5 (a HIT again)** as δ̇ tightens. A near-frozen fin flies the missile ~ballistically
and it hits by geometry. **This is the third occurrence of this pattern** (slice-5 σθ, slice-19
ρ — where the miss peaks at ρ≈0.5 and falls below it). Any δ̇ knob would need bounding to a
proven-monotone region.

**FINDING 6 — THE k_q AXIS (the advisor's redirect): NO CLEAN WINDOW EXISTS.** Sweeping
`k_q ∈ [0.3 … 0.0]` × `δ̇ ∈ [∞ … 1]` at the shipped `k_α = 1`, against the isolation bar
(δ̇=∞ stable AND finite δ̇ rings; `defl_sat == 0` EVERYWHERE; monotone):

| regime | `defl_sat` | miss | verdict |
|---|---|---|---|
| `k_q ≥ 0.02`, `δ̇ ≥ 2` (ζ_total ≳ 0.4) | **0 ✓** | **INERT (~29.5 m at every δ̇)** | passes the bar, teaches nothing |
| `k_q ≤ 0.01` or `δ̇ ≤ 1` (ζ_total ≲ 0.25) | **contaminated** | moves (64–130 m) | fails bar 2 |
| `k_q = 0` (ζ_total = 0.104) | contaminated | — | **RINGS AT δ̇=∞** ⇒ fails bar 1: a RINGY-AUTOPILOT lesson, not a rate-limit one |

**Every cell that shows drama fails the isolation bar; every cell that passes the bar is inert.**

**FINDING 7 — ⭐ THE STRUCTURAL RESULT (why no window can exist): `δ_max` SHADOWS `δ̇_max`.**
Findings 4 and 6 are the same fact on two axes. For the rate cap to bind, the fin must need to
move FAST. The fin needs to move fast **only** when the command moves fast — which requires high
`k_α` (finding 4) or low damping (finding 6). **Both drive `δ_cmd` past `δ_max` before the rate
cap can be the binding constraint.** And it is self-defeating from the other side too: raising
control authority `Cmδ` to buy deflection headroom SHRINKS the δ the loop needs, so the rate
limit matters even less. **On a statically-stable, aero-damped airframe with a properly-tuned α
loop, cap #5 is not independent of cap #3 — it is shadowed by it.** This is the general result,
and it is worth more than the slice would have been.

**FINDING 8 — the one clean effect that survives (and its honest ceiling).** In the isolated
window (`α_max = 0.8`, `k_q = 0.02`, `defl_sat == 0` ∀ δ̇ ≥ 2), the **fin tracking lag** is real,
monotone and cleanly attributable: `δ_lag = 0` (δ̇=∞) → **0.0899** (δ̇=2). But it **does not
propagate**: the miss stays ~29.5 m throughout, and even `α_lag` barely moves (0.2051 → 0.2077).
**The airframe's own short-period dynamics absorb the fin's lag before it reaches the flight
path.** A lesson whose entire content is "this knob moves a diagnostic that changes nothing"
is slice 15's headline again, one loop deeper — and shipping it twice in one arc is not a slice.

---

## THE LESSON — two candidates, gate 0 arbitrates *(SUPERSEDED — both DEAD; see FINDINGS)*

**Candidate A — THE GUIDANCE LIMIT CYCLE (the hoped-for headline).** The rate-limited fin cannot
slew fast enough to serve the α loop; the resulting phase lag turns the inner loop unstable and
δ/q/α **oscillate without decaying** — the fin goes bang-bang and the missile shakes itself off
the intercept. Slice 15's inert knob is lethal here *because* δ now feeds a moment rather than an
accel (finding 2).

- **The metric IS THE OSCILLATION, NOT THE MISS** (advisor). Slice 19's miss-ratio assertion
  cannot see a limit cycle — a NEW *kind* of gate-3 proof for the suite: sustained amplitude
  (a late-window amplitude that does NOT decay vs an early window) and/or a zero-crossing count
  of `q`/`δ` over a fixed late window, contrasted against the servo-absent slice-19 baseline
  where the same signals decay.

**Candidate B — THE α-ONSET-RATE CAP (the pre-named fallback).** No sustained cycle at any
physically plausible `δ̇_max`: then the rate limit adds phase lag ⇒ achieved α **lags** α_cmd ⇒
the lift ceiling `a_max_aero` **arrives late** ⇒ the miss opens further than slice 19's 295 m.
Distinct from slice 15's #2 (a g-onset cap on a direct accel map) by being one loop deeper —
the cap lands on **α̇**, and the g follows only after the airframe rotates.

Both are clean, both are shippable, both are distinct from all four prior caps. **Pick from the
probe, not from this document.**

---

## The scope

**IN:**
- A **scalar** first-order fin servo with a hard rate limit, stepped once per tick, between
  `alpha_autopilot_delta`'s `δ_cmd` and the δ `pitch_moment` consumes.
- A new pure primitive in `airframe.jl` + its tests.
- The presence-gated `airframe.delta_rate_max` loader key + `af_delta_rate_max` knob.
- Telemetry for the servo (achieved δ, δ̇, rate-sat flag), rung-gated.
- Scenario + verifier + UI test + smoke + shot (convention 14).

**OUT (named deferrals, unchanged):** the exponential atmosphere; induced drag; nonlinear
`C_L(α)` / true stall; bank-to-turn / 3-D; the radome/body-rate parasitic loop; a seeker in the
coupled loop.

**NOT REUSED: slice 15's Vec3 `FinState`** — `airframe.jl:261` already records why (a Vec3 in
the accel frame vs a scalar in rad; different frames, NOT literally composable). Slice 20 gets
its own scalar state. `guidance.jl`'s `fin_autopilot_step` is **TEXTUALLY UNTOUCHED**.

---

## Design decisions (advisor-reconciled)

0. **THE SERVO IS A PURE SLEW LIMITER — NO `τ_s` (advisor, load-bearing).**

   ```
   δ′ = δ + clamp(δ_cmd − δ, ±δ̇_max·dt)
   ```

   **Why this and not slice 15's `τ_s`-lag-plus-rate-clamp structure:** at `δ̇_max → ∞` a pure
   slew limiter **IS passthrough** ⇒ slice 19 recovered EXACTLY. A `τ_s` servo at `δ̇_max → ∞`
   is a first-order **lag**, NOT slice 19's instant δ — slice 15's own equivalence claim was to
   **`:pid`** (itself a lag), not to a passthrough, so importing its structure here would make
   the equivalence tooth in gate 1 FALSE, and the tempting fix (quietly setting `τ_s = dt`) is
   a fudge. Two lags would also muddy the lesson: with no `τ_s`, **the rate limit is the SOLE
   new effect** — the cleanest possible isolation for "same knob, inert then lethal", and
   rate-limited feedback is the textbook PIO case regardless.

   ⇒ **There is no `τ_s` anywhere in this slice.** `δ̇_max` is the only new parameter.

1. **The servo steps in `decide!` (phase 4), NOT `integrate!`.** `decide!` computes `δ_cmd` via
   `alpha_autopilot_delta`, steps its scalar servo state, and writes the **ACHIEVED** δ into the
   `:delta_cmd` comp key that `_integrate_coupled!` **already reads** (`missile.jl:201`).
   ⇒ **`_integrate_coupled!` is literally untouched** — the strongest possible byte-identity
   guarantee — and it is consistent with δ already being a **zero-order hold across the RK4
   stages** (the entry reads it once). *Name the tick-rate ZOH as a §1 approximation*: honest at
   `dt = 1e-3` because `1/δ̇_max` is ≫ 1 ms.
   - **Key-naming wart, accepted deliberately:** `:delta_cmd` then holds the *achieved* δ under
     the servo and the *commanded* δ without it. Keep the key (renaming would touch the
     integrate! seam and forfeit the byte-identity win); document it precisely as **"the
     deflection the airframe flies this tick."**
2. **Byte-identity: key-absent ⇒ no servo ⇒ slices 16/17/19 bit-identical.** The δ̇→∞ equivalence
   is slice 15's precedent, now via key presence (finding 1). A servo-absent run must be
   **bit-exact**, asserted, not assumed.
3. **State: a NEW scalar comp key** (`:af_delta_state`), lazily initialized to the authored
   `af_delta` trim (default 0) so tick 1 injects no transient — matching slice 19's existing
   tick-1 behaviour (`integrate!` precedes the first `decide!`).
4. **Gate on `:autopilot === :alpha` AND `:airframe === :pitch_coupled` AND the key** — under
   `:point_mass` the fin is not in the loop at all. This **deepens slice 19's cross-fidelity
   dependency** (the first in the suite); state the gate explicitly rather than letting it fall
   out of the code.
5. **A KNOB, NOT A FIDELITY RUNG.** `δ̇_max` is the lesson slider; no 5th `:autopilot` rung.
   Precedent: slice 16's `af_cma` — a live knob that changes physics without being a fidelity
   button (and the convention-4c trap argues *against* a rung that names a plant it only
   parameterizes). *Considered and rejected:* a `:alpha_fin` rung — it would force a scenario
   split for a lesson that reads better as one continuous slider (slice 15's own δ̇ sweep is the
   model). ⇒ The shared client button keeps cycling slice 19's `airframe` toggle; slice 20 is a
   **slider lesson**, exactly as slice 16 was.
6. **Class 4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance
   VACUOUS", the 6th consecutive after 14/15/16/17/19). Live-settable, no `set_fidelity` guard.
7. **Crash-safety (convention 5):** `δ̇_max` is a live slider ⇒ clamp at the consumer
   (`max(·, _FRAME_EPS)`, the slice-15 precedent) + load-validated `> 0` and finite for the
   authored value. **No new divide** (design 0 — a slew limiter has no `1/τ_s`), so no new
   floor site.

---

## The three gates

### 0. Probe — THE LIMIT-CYCLE HUNT (throwaway, `M:\claud_projects\temp\slice20_probe\`)

**This gate decides the slice's headline.** Sweep `δ̇_max` at the **shipped** `k_α = 1`, `k_q`,
`Cmδ = 3` and hunt a *sustained* oscillation in δ/q/α — amplitude NOT decaying over several
short-period cycles (`ω_sp` is known: `short_period_freq`). Record FINDINGS in this file's style.

Questions the probe must answer:
- Does a sustained cycle exist at any physically plausible `δ̇_max`? At which values? → A or B.
- If A: what is the discriminating metric (late/early amplitude ratio? `q` zero-crossings?), and
  does it read cleanly against the servo-absent baseline?
- If B: how much does the miss open past slice 19's 295 m, and is the α lag measurable/pinnable?
- **Does `defl_sat` stay 0?** Slice 19 pins `defl_sat == 0` structurally so `δ_max` is provably
  not binding. **A bang-bang limit cycle may drive δ into `δ_max` and contaminate the claim**
  (cap #3 masquerading as cap #5) — the isolation must be re-established, NOT copied from slice
  19. Same for `max(a_max_aero) < a_max` (269 ≪ 3000).
- (**RESOLVED before the probe — design 0:** the servo is a pure slew limiter, no `τ_s`. Probe
  THAT structure; do not reintroduce a lag to chase a cycle.)

### 1. `airframe.jl` primitive green (pure, RNG-free, no LinearAlgebra — §9 house style)

A scalar servo function + tests: the **δ̇→∞ / key-absent equivalence** (the false-fidelity
tooth — a linear servo with no limit must reproduce the passthrough exactly), the rate cap
holding (`|δ̇| ≤ δ̇_max` everywhere by construction), the sign, and an explicit-`atol` transient
against a hand-integrated reference (convention 11 — no rtol-`≈0` tautology).

### 2. Wired — the servo in `Autopilot.decide!` + the loader key

The `decide!` seam (design 1), `:af_delta_state`, the presence-gated loader key + validation,
rung-gated telemetry (the slice-17 lift-keys / slice-19 α-keys precedent — gate on the SERVO,
not on `af_cma`, or a slice-19 wire breaks). `LIVE_FIDELITY_MODES` untouched (no new rung);
`af_delta_rate_max` declared as a knob. **Assert slices 16/17/19 byte-identical.**

### 3. Scenario + Godot view + four proofs (convention 14)

`scenarios/slice20_*.yaml` (one lesson — convention 9). Reuse the slice-19 airframe view
(`_fid_kind="airframe"`) + the aero strip; the headline tell (a δ/α trace showing the ring, or
the lag) is a gate-3 design once gate 0 has named the lesson. Four proofs: verifier (the lesson
as a number + held-seed bit-identical replay), UI test, smoke-load, windowed shot. Re-smoke
16/17/18/19.

---

## Watch-items

- **The `defl_sat` contamination risk** (gate 0, above) — the single most likely way this slice
  ships a false claim.
- **`:delta_rate_max` vs `:af_delta_rate_max`** — never let the two meet in a sentence without
  naming the plant (finding 2). Grep both before writing any doc line.
- **The frozen gains.** If the lesson only appears at `k_α ≫ 1`, that is **NOT a shippable
  headline** — it erodes slice 19 (FINDING 14). It is candidate B, honestly reported.
- **Tick-1 transient** — init the servo state to `af_delta`, not to `δ_cmd`.
- **`_finite`/`_finite_coord` on all new telemetry** (convention 6).
- **The client value-guard, THREE ways already** (16 drops the button / 17+19 show it / 18 stays
  3-D). Slice 20 adds no button — verify it does not disturb that guard.

---

## Task checklist

- [ ] Gate 0 — the limit-cycle hunt; record FINDINGS; **name the lesson (A or B)**; advisor pass
      on the finding before gate 1.
- [ ] Gate 1 — `airframe.jl` scalar servo + `test_airframe.jl` teeth; `pwsh tools/test.ps1` green.
- [ ] Gate 2 — the `decide!` seam + loader key + telemetry; byte-identity assert for 16/17/19.
- [ ] Gate 3 — scenario + view + the four proofs; re-smoke 16/17/18/19.
- [ ] Docs — `docs/STATUS.md` as-built, `CLAUDE.md` status line, `HANDOFF.md` §11 Tier-A entry,
      memory (`ewsim-fin-dynamics-direction.md` — the arc pointer).
