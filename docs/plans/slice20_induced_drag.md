# Slice 20 — INDUCED DRAG: the missile lowers its own ceiling (§11 Tier-A)

> **The slice-20 slot was vacated.** `docs/plans/slice20.md` holds the DEAD candidate (a
> rate-limited fin inside the coupled loop), killed at gate 0 because `δ_max` structurally
> SHADOWS `δ̇_max`. That record stands; this is a different slice in the same slot. Induced
> drag is a NAMED deferral of slices 17/19 ("induced drag — the g-bleeds-V-lowers-Q spiral").

**STATUS: GATE 0 COMPLETE — the lesson is NAMED and the window is PROVEN. Gate 1 next.**

---

## The physics

    C_L   = C_Lα·α                        (the shipped linear lift curve — airframe.jl)
    C_Di  = K·C_L²                        (the induced-drag polar; K the LUMPED factor)
    a_ind = −(Q·S·K·C_L²/m)·v̂             (ALONG −v̂ — it BILLS you for the lift)

`K` is lumped (the `cd_area` = "lumped Cd·A" precedent) rather than decomposed into
`1/(π·e·AR)`: this airframe's `C_Lα = 20/rad` is AUTHORED high (slice 17/19's choice), so
`C_L` reaches ≈3 at α = 0.15 and the K that produces a visible spiral is correspondingly
large. **Do NOT quote an implied aspect ratio** — `C_Lα` is not derived from geometry here,
so `K = 1/(π·e·AR)` would be a false precision. K is authored to the same standard as the
rest of this airframe (a §1 named approximation).

## THE LESSON — *the missile lowers its own ceiling by maneuvering*

Slice 19: the maneuver ceiling `a_max_aero = Q·S·C_Lα·α_max/m` is a FLIGHT CONDITION; it
binds, and you miss. **Slice 20: the ceiling is a flight condition YOU DEGRADE BY USING IT.**

    pull α → pay K·C_L² in drag → V falls → Q = ½ρV² falls → the ceiling falls
           → the ceiling catches the demand → you cannot pull → you miss

**The FIRST POSITIVE-FEEDBACK LOOP in the project.** And it cashes an approximation slices
17/19 shipped EXPLICITLY: *"lift is drag-free / speed-preserving (⟂ v)"*. Lift ⟂ v turns the
path; induced drag ∥ −v̂ sends the invoice.

**The headline number is `aero_sat: 0% → 61%`** — with the geometry, the target, α_max and ρ
ALL HELD, and ONLY K changed. At K=0 the aero ceiling is *not a factor at all* (it never
binds once in the guided window). Nobody lowered it; the missile lowered it, by turning.

---

## GATE-0 FINDINGS (7 probes — THE RECORD)

Probes at `M:\claud_projects\temp\slice20_drag_probe\` (`common.jl`, `probe.jl`…`probe7.jl`).
(NB: `slice20_probe\` is the DEAD fin slice's record — untouched.) All drive the **SHIPPED**
primitives (`alpha_command` / `alpha_autopilot_delta` / `pitch_moment` / `lift_accel` /
`rk4_coupled` / `pn_accel` / `clamp_accel` / `total_accel` — convention 10) with the drag term
inserted into the coupled stage force.

**FINDING 1 — the probe is EXACT.** `K = 0` reproduces the shipped slice-19 wire *to the
digit*: **miss 295.168 m** (shipped: 295.168), sat 0.592 (shipped 0.59), defl_sat 0, t_cpa
4.131. The replication is trustworthy — a stronger validation than the dead fin-probe's
294.879-vs-295.168.

**FINDING 2 — SLICE 19's SCENARIO IS UNUSABLE (the peg trap; the fin slice's FINDING 2
recurring one slice later).** At the shipped `α_max = 0.2` the α command is PEGGED at the
clamp **59.2%** of the run. A pegged command is a CONSTANT command ⇒ α ≈ const ⇒
`K·C_L²` ≈ const ⇒ **induced drag degenerates into PARASITIC drag in a costume** (the
convention-4 false-fidelity trap, 5th occurrence in this arc). Slice 20 needs α to TRACK
DEMAND.

**FINDING 3 — UNPEG BY LOWERING THE DEMAND, NOT BY RAISING α_max.** Raising α_max unpegs
(0.8 ⇒ sat 8.9%) but costs physicality — 0.8 rad = **46°**, an absurd stall limit — and blips
`defl_sat` off zero. Lowering the ENGAGEMENT's demand instead keeps slice 19's ENTIRE airframe
verbatim (α_max = 0.2 rad ≈ 11.5°, defensible) and changes only the geometry.

**FINDING 4 — ⭐ THE DISCRIMINATOR IS ABSOLUTE (on a straight flight).** Over a 4 s straight
fly-out (α_pk = 0.0018):

| drag | ΔV billed |
|---|---|
| induced `K = 0.1` | **0.03 m/s** |
| induced `K = 0.2` | **0.06 m/s** |
| parasitic `cd_area = 0.01` | **75.6 m/s** |
| parasitic `cd_area = 0.02` | **136.3 m/s** |

Induced drag bills a non-maneuvering missile **NOTHING** (α² = 0); parasitic bills it anyway.
**K is provably NOT `cd_area` in a costume** — with a number, not an argument.

**FINDING 5 — ⚠️ THE CLAIM IS BOUNDED: THE DOWNSTREAM IS GENERIC TO ANY SPEED LOSS.** Matched
on ΔV over the *maneuvering* run, parasitic reproduces induced almost exactly:

| drag | ΔV | miss | ceiling at CPA |
|---|---|---|---|
| induced `K = 0.1` | 133.8 | **44.17 m** | **176.3** |
| parasitic `cd = 0.016` | 138.7 | **45.02 m** | **173.2** |

⇒ **"bleed → Q → ceiling → miss" is NOT evidence of INDUCED drag** — it is what ANY speed loss
does. Only the SOURCE of the bleed is distinctive (FINDING 4). **This bounds the shippable
claim and MUST be written into the scenario/docs**, not discovered by a reader. The honest
split:
- **induced = a CLOSED LOOP** — the bill is written BY THE MANEUVER (∝ α²); self-inflicted.
- **parasitic = an OPEN-LOOP TOLL** — set by `cd_area`, arrives whatever you do.

**FINDING 6 — THE MONOTONICITY REVERSAL RECURS — OCCURRENCE #4**
([[ewsim-df-ellipse-sigma-monotonicity]]; slice-5 σθ, slice-19 ρ, the fin slice's FINDING 5).
The miss is **NON-MONOTONE in K**: at 6 km/a_lat 100 it runs 30.5 → 91.8 (**peak at K≈0.3**)
→ 90.3 → **33.1 at K=0.8** (a "hit"!) → 125 → 166. Past K≈0.3 the missile bleeds to ~96 m/s,
stops trying, flies ~ballistically and passes CLOSE by geometry — the exact inverse of the
lesson. `defl_sat` also explodes there (15 → 253). **The knob range MUST be bounded to the
proven-monotone, defl-clean region K ∈ [0, 0.3].**

**FINDING 7 — ❌ A PREDICTION REFUTED: "harder demand → bigger bill" IS FALSE AS STATED.**
Holding the drag fixed and varying the target's maneuver, the *attributable* induced bill
**FALLS**: a_lat 0 → 100 → 200 gives 194.4 → 116.7 → 126.7 m/s (parasitic: 104.4 → 94.5 →
93.4, flat). `a_lat` is a CONFOUNDED demand lever — a harder-maneuvering target SHORTENS
time-of-flight (4.74 → 4.13 s) so there is less flight to accrue the bill, and the α_max clamp
caps α anyway (α_pk ≈ 0.14 regardless). **Do NOT ship "a harder engagement costs more".** The
straight-vs-intercept contrast (FINDING 4) and the within-run α-tracking trace (FINDING 9) are
what carry the "you pay for the turn" claim.

**FINDING 8 — ⭐ THE `defl_sat` BLIPS ARE ENDGAME ARTIFACTS, AND SLICE 19 CANNOT BE COPIED
HERE.** Every `defl_n > 0` in the grid appears ONLY in configs that actually REACH the target.
With `r_stop = 0`, PN's `ω → ∞` as `r → 0` ⇒ `a_cmd` spikes to `a_max` in the last ticks ⇒
`δ_raw` punches `δ_max`. **Under an LOS gate (`r > 300 m`, `t > 0.2 s`) every blip vanishes —
`defl_sat == 0` at every K, in every finalist.** Slice 19 could pin the UNGATED count only
BECAUSE it misses by 295 m and never enters that regime; **a HIT scenario cannot, and must
LOS-gate the window** ([[ewsim-missile-verifier-sampling]] — the memory names this exact
trap). The fourth-cap isolation is recoverable, but by gating, NOT by copying slice 19's
assertion.

**FINDING 9 — ⭐ THE PICK AND THE HEADLINE.** Target at **9 km, NON-maneuvering** (a_lat 0 ⇒
plain `ConstantVelocity`), slice-19's airframe/autopilot **verbatim** (α_max 0.2, C_Lα 20,
Cmα −1, Cmδ 3, Cmq −150, I 20, k_α 1, k_q 0.3, δ_max 0.4, a_max 3000, ρ 1.225, cd_area **0**).
K ∈ [0, 0.3], LOS-gated:

| K | miss | V at CPA | ceiling at CPA | **aero_sat** | defl_sat |
|---|---|---|---|---|---|
| 0.0 | **1.27 m — HIT** | 663.6 | 242.1 | **0.0 %** | 0 |
| 0.02 | 2.28 | 644.0 | 228.0 | 0.8 % | 0 |
| 0.05 | 5.89 | 608.6 | 203.6 | 3.3 % | 0 |
| 0.10 | 28.04 | 530.3 | 154.6 | 10.4 % | 0 |
| 0.15 | 103.07 | 433.3 | 103.2 | 22.2 % | 0 |
| 0.20 | 263.20 | 338.8 | 63.1 | 37.7 % | 0 |
| 0.25 | 483.96 | 265.0 | 38.6 | 51.5 % | 0 |
| 0.30 | **714.10 m — MISS** | 212.7 | **24.9** | **61.1 %** | 0 |

**MONOTONE IN EVERY COLUMN.** HIT → MISS = **562×**; the ceiling collapses **10×**; α_pk
0.133 → 0.177 stays UNDER α_max (demand-limited, never clamp-pegged ⇒ FINDING 2 avoided);
gated `defl_sat == 0` throughout ⇒ the FOURTH cap provably clean.

**`aero_sat 0.0% → 61.1%` IS THE HEADLINE**: at K=0 the ceiling NEVER BINDS ONCE. The missile
brings it down on itself.

**FINDING 10 — the within-run trace: the bleed TRACKS |α|** (6 km/a_lat 100, K=0.2, per 0.5 s):

| window | α | ΔV in that window |
|---|---|---|
| t 0.5→1.0 (hard turn) | 0.136 → 0.145 | **−47.8 m/s** |
| t 2.0→2.5 (coast) | 0.090 → **0.017** | **−8.8 m/s** |
| t 3.5→4.0 (hard turn) | −0.143 → −0.149 | **−31.6 m/s** |

The coast is nearly FREE; the turns are expensive. This is the induced signature *inside a
single run* (parasitic ∝ V² would bleed hardest EARLY, when fastest — the opposite shape).
Meanwhile at K=0 the ceiling is FLAT (268.5 → 256.7, −4%) where at K=0.2 it COLLAPSES
(247.4 → 113.1, −54%) over the same engagement.

---

## Scope

**IN:** a pure `induced_drag_accel` primitive in `airframe.jl` + tests; a 9th `AirframeParams`
field `K` (LAST — the `Cla` precedent) with an outer constructor defaulting it to 0.0 so the
existing 8-arg sites (4 in `missile.jl`, 5 in tests) keep compiling; the presence-gated loader
key; the `af_k_induced` knob bounded to **[0, 0.3]**; rung/mode-gated telemetry; scenario +
verifier + UI test + smoke + shot (convention 14).

**OUT (named deferrals):** the exponential atmosphere ρ(z); nonlinear `C_L(α)` / true stall;
bank-to-turn / 3-D; the radome/body-rate parasitic loop; a seeker in the coupled loop; a
rate-limited fin (DEAD — see `slice20.md`); zero-lift-drag `C_D0` interaction (cd_area exists
but is held 0 for the isolation).

## Design decisions

1. **BYTE-IDENTITY VIA A CONDITIONAL CLOSURE BRANCH (advisor, load-bearing)** — gate on
   `haskey(c, :af_k_induced)`, mirroring the `:a_ctrl` pattern at `missile.jl:113`. **NEVER** an
   unconditional `+ induced_drag_accel(...)` trusting `K = 0 → zero`: `-0.0 + 0.0 → +0.0`
   flips a bit and the reinterpret determinism tests catch it (the codebase documents this
   exact trap). Slices 16/17/19 must be bit-identical — ASSERTED, not assumed.
2. **The drag reads the STAGE α (`TH − γ`)**, never the entry θ — the slice-17 stage-θ advisor
   catch applies identically inside `rk4_coupled`.
3. **K IS THE CAUSATION LEVER — NOT α_max (advisor, load-bearing).** In slice 19 α_max was
   clean because it touched ONLY the α_cmd clamp. **Here α_max ALSO feeds induced drag through
   the achieved α** (pull harder AND bleed more — two competing effects), so it is NO LONGER
   ISOLATED and can never be this slice's counterfactual. **K enters ONLY the drag term.**
4. **Knob range [0, 0.3]** — bounded to the proven-monotone, defl-clean region (FINDING 6).
5. **`cd_area` held 0** — every m/s lost is then provably bought with α (the isolation).
6. **Class 4c** (physics-changing, NO RNG — truth-fed PN, no seeker ⇒ "draw-count invariance"
   VACUOUS; live-settable, no `set_fidelity` guard) — the 6th 4c after 14/15/16/17/19.
7. **The verifier LOS-GATES its sat/defl window** (FINDING 8) — it must NOT copy slice 19's
   ungated `defl_sat == 0`.

## OPEN — for the gate-0 advisor pass

**Mechanism: a KNOB or a FIDELITY RUNG?** The scenario's contrast (HIT↔MISS) is exactly the
shape the shared client button carries, but the "off" rung is just `K = 0`, which risks being a
knob in a button costume. Precedent cuts both ways: slice 17 made `:airframe` a rung though
`Cla = 0` emulates `:point_mass`; slices 16/19 shipped slider-only lessons. Candidate naming if
a rung: `:lift_drag = (:free, :induced)` — ":free" names slices 17/19's approximation exactly.

## The three gates

- [x] **Gate 0** — the spiral hunt. FINDINGS above; lesson NAMED; **advisor pass before gate 1**.
- [ ] **Gate 1** — `induced_drag_accel` + `AirframeParams.K` + `test_airframe.jl` teeth: the
      `K = 0` passthrough (`==`), the α² scaling, the −v̂ direction (`dot(a_ind, v̂) < 0` AND
      ⟂-component == 0 — lift's mirror), the α → −α symmetry (the bill is even), explicit
      `atol`. `pwsh tools/test.ps1` green.
- [ ] **Gate 2** — the closure branch + loader key + telemetry; **assert 16/17/19 byte-identical**.
- [ ] **Gate 3** — scenario + view + four proofs; re-smoke 16/17/18/19.
- [ ] **Docs** — `STATUS.md`, `CLAUDE.md` status line, `HANDOFF.md` §11, memory.

## Watch-items

- **The FINDING 5 overclaim** — the single most likely false claim in this slice. The spiral's
  downstream is generic; only the SOURCE is induced-specific. Never write "the spiral proves
  induced drag."
- **FINDING 7** — never write "a harder engagement costs more". Refuted.
- **The peg trap (FINDING 2)** — if a knob/geometry edit ever pushes `aero_sat → 1.0`, the
  lesson silently reverts to parasitic-in-a-costume. The verifier should assert α is NOT pegged.
- **Non-monotone past K ≈ 0.3** (FINDING 6) — the knob max is load-bearing, not cosmetic.
- **The endgame gate (FINDING 8)** — an ungated `defl_sat == 0` assert WILL fail on a HIT.
- `_finite`/`_finite_coord` on all new telemetry (convention 6).
- **Grep every `AirframeParams(` site** before adding the 9th field (4 in `missile.jl`, 5 in
  tests) — the outer constructor must keep them compiling.
