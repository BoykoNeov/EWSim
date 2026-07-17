# Slice 21 — the EXPONENTIAL ATMOSPHERE `ρ(z) = ρ₀·exp(−z/H)` (§11 Tier-A)

**Status: PLANNED (gate 0 not yet run).** The honest completion of slices 19+20's constant-ρ
approximation — the deferral both of them shipped explicitly, and the one that finally makes
**"high altitude" a REAL lever** instead of a phrase the docs forbid.

Slice 19 named the flight-condition ceiling `a_max_aero = Q·S·C_Lα·α_max/m` and moved it with the
`rho` knob — **an ENGINEER dialling a flight condition**. Slice 20 made the missile move it **by
turning** (V bleeds → Q falls). Slice 21 makes it move **by CLIMBING**: the air itself is a
function of WHERE you fly, so the ceiling you need in order to reach a high target is the ceiling
that reaching for it takes away.

> ⚠ **The phrase this slice retires.** slices 19/20 are under standing orders to say *"low dynamic
> pressure (thin air / slow)"* and **NEVER** unqualified *"high altitude"* — because ρ was
> AUTHORED, not derived from z. When this slice lands **that caveat lifts, but ONLY inside a
> scenario carrying `af_scale_height`.** A slice-19/20 wire has no such key and its ρ is still a
> constant an engineer typed: the old language still governs there. Do not do a global find/replace.

---

## Read these FIRST — three things found while planning

### 1. THE STAGE-`P` ARG IS ALREADY THERE, AND IS UNUSED TODAY (the whole slice hinges on it)

`_integrate_coupled!`'s joint derivative closure is `f(P, Vv, TH, Q)` (missile.jl ~221/228). **`P`
— the RK4 STAGE POSITION — is passed to both arms and read by NEITHER.** Slice 17 built the joint
`[pos, vel, θ, q]` stepper so the coupling could re-evaluate `(V, γ)` mid-stage; it threaded the
stage position through for free and nothing has ever needed it.

**The exponential atmosphere is the thing that finally uses it — at ZERO contract change.** This is
the correct decomposition, not merely the cheap one (advisor): the joint stepper already carries the
state that ρ(z) needs, so slice 21 lands entirely inside the coupled branch.

**This is the direct analog of slice 17's STAGE-θ FIX** (missile.jl ~206, load-bearing): the
closure MUST read the stage `P[3]`, **NEVER** the entry `e.pos` closed over above. Entry-z is
O(dt²) off per step, compiles clean, and — exactly like the entry-θ bug — will be INVISIBLE to a
steady-state ceiling-factor test. **Only a transient golden catches it.** Pin it the same way.

### 2. THE POINT-MASS DRAG PATH CANNOT FOLLOW, AND MUST NOT BE DRAGGED ALONG

`dynamics.jl`'s steppers take `accel` as a closure **`v -> a(v)`** and are documented as such
("the steppers never see rho/cd/mass", `rk4_step` calls `accel(v)` — no position anywhere). An
exponential atmosphere on the **parasitic** drag path therefore needs the contract changed to
`(p, v) -> a`, touching slice 8's `rk4_step`/`euler_step` — i.e. the byte-identity surface of every
ballistic slice, **for a path that carries no altitude lesson**.

**DEFERRED, EXPLICITLY AND BY NAME** (advisor): *the exponential atmosphere on the ballistic
point-mass drag path deserves its own slice; it is not a rider on this one.* The `(p,v)->a`
contract change is the entire cost of that slice and should be paid deliberately.

**The boundary is therefore nameable and clean, NOT a hidden approximation (§1):**
- **Inside `_integrate_coupled!`** (where the airframe is): parasitic drag + lift + induced drag +
  the pitch moment ALL see the **same stage ρ(z)**. Fully self-consistent — the stage ρ goes to the
  `AirframeParams` rebuild **AND** the `total_accel(Vv; rho = …)` call in the same closure.
- **The point-mass branch** (slices 8–16, no airframe): constant ρ. Byte-identical, and it has no
  lesson to carry.

### 3. THE FALSE-FIDELITY TENSION — RESOLVED, AND IT SHIPS AS A TOOTH

The sharpest risk in this slice: **is `H` just slice-19's `rho` knob relabeled?** If all H does is
scale ρ at a fixed altitude then slice 21 IS slice 19 wearing a hat — the false-fidelity trap, and
this arc has already been bitten by it FIVE times (15's k_δ cancellation, 16's refused toggle, 19's
a_ctrl-in-the-coupled-force, 19's dead `speed` knob, 20's pegged-α → parasitic-in-a-costume).

Both halves are true at once, and the plan must write BOTH down:

- **NO RUNG** — the constant-ρ state IS the `H → ∞` limit / the key-absent state. A rung must name
  physics the knob cannot express, and `:constant` is a state the knob already reaches. **This is
  exactly the slice-20 shape (`:free` IS `K = 0`) and the slice-16 shape (`af_cma`).**
  `LIVE_FIDELITY_MODES` is **UNTOUCHED**.
- **NOT FALSE FIDELITY** — finite `H` expresses **z-VARYING ρ profiles that NO CONSTANT ρ CAN
  PRODUCE**. Slice 19's knob offers the family of *constant* profiles; ρ(z) offers *exponential-in-z*
  profiles. **The new degree of freedom is THE GRADIENT** — the difference between the ceiling at
  launch altitude and the ceiling at intercept altitude. **A single constant cannot match both
  ends.** That passes the "names physics the knob can't express" test.

These are consistent: **the OFF state coincides with the old approximation (⇒ no rung), the ON
states reach genuinely new physics (⇒ not false fidelity).** The slice-20 K precedent exactly.

> **The corollary that shapes the SCENARIO:** the lesson only exists if **the missile TRAVERSES
> ALTITUDE during the run**. A coupled missile flying a level intercept at a fixed z would make H a
> pure ρ-rescale — i.e. slice 19 relabeled. **The engagement MUST climb (or dive).** This is a
> hard scenario constraint, not a preference.

---

## THE LESSON — mirror slice 20's structure exactly

**⭐ THE HEADLINE — the CEILING FACTOR `ρ(z)/ρ₀ = exp(−z/H)`, collapsing WITHIN one run.**

Pure z. **No V confound at all** (unlike slice 20's collapse ratio, which is a V story), and
monotone in both z and H **by construction** — `exp` cannot reverse. At the standard H = 8500 m:

| z (m) | ρ(z)/ρ₀ | the ceiling the air will give you |
|------:|--------:|-----------------------------------|
| 3 000 | 0.70    | slice 20's launch altitude — already −30% |
| 4 200 | 0.61    | slice 20's target altitude |
| 10 000| 0.31    | a 2.3× collapse from launch, from CLIMBING ALONE |
| 15 000| 0.17    | −83% |

**The corroborator — the TWIN IS KEY PRESENCE, not a slider value** (the slice-20 `K=0` vs
`K=0.3` / slice-19 α_max-counterfactual structure): constant-ρ (key ABSENT) **HITS** — it believes
the air at 12 km is as thick as at sea level — while ρ(z) **MISSES**. Same geometry, same target,
same ρ₀/α_max/mass/K.

**THE MISS IS THE CORROBORATOR, NEVER THE HEADLINE.** Expect the reversal at small H (advisor, and
this is the **[[ewsim-df-ellipse-sigma-monotonicity]] pattern, 5th occurrence**): as H → small the
air thins to nothing, the missile stops trying, flies ~ballistically, and **the miss SHRINKS** —
the exact inverse of the lesson. **Bound the H slider to the MEASURED monotone region** (gate 0).

**THE ISOLATION — hold `K = 0` AND `cd_area_m2 = 0` in the showcase.** Then the ONLY thing lowering
the ceiling is ρ(z). Gravity still bleeds V on a climbing missile (slice 20 measured that residual
at 8% — "the 0.92× at K=0 is GRAVITY") — **but the constant-ρ twin carries that SAME gravity bleed,
so the twin DIFFERENCE is the pure z contribution.** Report **the twin RATIO**; do **NOT** claim an
additive V-vs-z decomposition (advisor — slice 20 reported K=0 vs K=0.3 rather than subtracting,
and for the same reason).

### The `a_ind ∝ 1/Q` compose — VERIFIED, but a TOOTH, not the headline

Substituting the α the autopilot must command, `α = a_perp·m/(Q·S·C_Lα)`, into the bill:

```
|a_ind| = Q·S·K·C_Lα²·α²/m  =  K·m·a_perp² / (Q·S)      ∝ 1/Q
```

**The same demanded turn costs MORE speed at altitude.** A lovely second-order compose of 20 into
21 — but **convention 9**: slice 20 already teaches the bill, and re-teaching it here muddies the
new z→ρ→ceiling axis. **Ships as a test tooth (with K > 0) + a named observation. The showcase
stays on the ceiling factor with K = 0.**

---

## The scope

**IN:** `atmosphere.jl` (one pure function); stage-z ρ inside `_integrate_coupled!`; ρ(z) at the
decide!/telemetry `AirframeParams` sites; the loader key + the `af_scale_height` knob; a climbing
showcase scenario; the four proofs.

**OUT (named):** the `(p,v)->a` contract change / ρ(z) on the ballistic point-mass drag path (§2
above); a LAYERED / standard-atmosphere table (troposphere lapse + stratosphere — the exponential is
the honest single-parameter stand-in, the `cd_area`-is-lumped precedent); temperature/speed-of-sound
→ Mach-dependent `C_Lα` (a much bigger slice, and the aero lib is deliberately Mach-free);
ρ(z) for the RF/propagation side (that is §11's *separate* "layered atmosphere, ducting" entry
behind the `propagation` knob — **do not conflate the aero atmosphere with the RF one**).

---

## Design decisions (advisor-reconciled)

1. **`atmosphere.jl` is the ONLY new pure code, and the aero lib NEVER LEARNS ABOUT ALTITUDE.**
   `lift_accel`/`induced_drag_accel`/`pitch_moment`/`aero_accel_limit`/`alpha_command`/
   `short_period_freq` keep reading `p.rho` — **unchanged, z-free, measurement-agnostic (§12)**.
   They just get a `p` whose `rho` is the stage value.
2. **Rebuild `AirframeParams` PER STAGE** rather than threading a `rho` kwarg through six aero
   functions. `AirframeParams` is isbits — a per-stage rebuild is stack-allocated and free. This is
   what keeps decision 1 true.
3. **NO new fidelity rung. ONE knob: `af_scale_height` (H, metres), presence-gated.** Key absent ⇒
   constant ρ ⇒ **slices 1–20 byte-identical**. (§3 above for why both halves hold.)
4. **TWO CLOSURES, gated on `haskey(c, :af_scale_height)`; the else-arm is slice 17/19/20
   TEXTUALLY VERBATIM.** Do NOT compute `ρ_stage` unconditionally and lean on `exp(0)==1` — the
   slice-20 discipline: `0.0*v` mints `-0.0`, `a + (-0.0)` flips a bit, and the reinterpret
   determinism tests catch it. **Gate on KEY PRESENCE, never on the identity.** (The *test* may
   assert the H→∞ identity; the *live path* may not rely on it.)
5. **The knob is H and ONLY H. Launch/target ALTITUDE ARE DEAD KNOBS** — position is consumed once
   at load and `reset` reloads the YAML. **This is the exact `speed` trap that bit slice 19 at gate
   3** (swept by re-authoring per run at gate 0, and a no-crash test PASSES on a dead knob). H is
   read per-tick from `comp` by both `integrate!` and `decide!` ⇒ zero new consumer plumbing, the
   slice-19 `rho` shape. **Ship the NOT-A-DEAD-KNOB TRIPWIRE** (verifier + `test_server`: assert H
   MOVES the ceiling factor, not merely that nothing threw).
6. **Convention-6 floor inside `air_density`.** An RK4 stage can probe `P[3] < 0` (a low/diving
   pass, or a wild transient stage excursion); `exp(−z/H)` at a catastrophic negative z mints
   `Inf` → NaN into `pos` → an invalid frame, and a throw in `integrate!` lands in the session's
   IO/EOF-only catch and **silently drops the connection**. Floor z at 0 (⇒ ρ ≤ ρ₀ — physical:
   below sea level the model simply stops thickening). `H > 0` validated at LOAD **and** floored at
   the consumer (it is a live slider — convention 5's two guard sites).
7. **Class 4c** — physics-changing, NO RNG (truth-fed PN, no seeker ⇒ **"draw-count invariance" is
   VACUOUS; do NOT copy the slice-11/13 draw language**). Live-settable, **no `set_fidelity`
   guard**. **The 7th consecutive 4c** (14/15/16/17/19/20/21).
8. **Client: expect ZERO new code** (the slice-20 outcome). Slice 19's aero strip already plots the
   ceiling; **it just starts falling for a NEW reason.** Confirm, don't assume.

---

## The three gates

### 0. Probe — EMPIRICAL, throwaway, `M:\claud_projects\temp\slice21_probe\`

Nothing below is committed until gate 0 measures it (the slice-19/20 discipline — gate 0 KILLED
slice 20's first design and slice 19's `speed` knob).

- **P1 — the showcase geometry.** Find a climbing engagement where the ceiling factor collapses
  hard (target at 10–15 km?) AND the first-CPA condition holds (target OUTRUNS missile — the
  [[ewsim-missile-verifier-sampling]] constraint) AND α tracks demand rather than pegging the clamp
  (**slice-20 gate-0 FINDING 2**: a pegged α is a constant α — here it would flatten the very
  gradient the slice is about).
- **P2 — the twin.** Does key-absent HIT and ρ(z) MISS at the same geometry? By how much?
- **P3 — the H sweep.** Measure the miss vs H and **FIND THE REVERSAL** (advisor predicts small-H
  → the missile gives up → the miss shrinks). Bound the slider to the monotone region with a
  measured margin (slice 20 shipped a 2× margin on K).
- **P4 — the LEAK check.** Does α_pk overshoot α_max anywhere in the H range (slice-19's ceiling
  leak, which contaminated slice 20 from K ≥ 0.8)? Does `defl_sat` stay 0 in the LOS-gated window?
- **P5 — the stage-z fix.** Measure entry-z vs stage-z divergence. **Expect it to be TINY** (slice
  17's entry-θ bug was ~0.019 m / 8 s) — which is the POINT: it must be pinned by a transient
  golden, because no steady-state test will ever see it.

### 1. `atmosphere.jl` primitive green (pure, RNG-free, no LinearAlgebra — the §9 house style)

`air_density(z; rho0, H)`. Closed-form teeth: the z=0 identity (`== rho0`, bit-exact); the
one-scale-height point (`ρ(H)/ρ₀ == exp(-1)`); **the H→∞ limit ⇒ `== rho0` BIT-EXACT** (the
no-rung argument, pinned as a test); the negative-z floor (convention 6); monotone-decreasing in z.
Included **before `missile.jl`** (no mode-const ⇒ no `LIVE_FIDELITY_MODES` ordering constraint).

### 2. Wired — stage-z in the coupled closure + the loader key

The two-closure gate; the per-stage params rebuild; ρ(z) at the decide!/telemetry sites
(missile.jl ~272, ~320, ~637–645) via `air_density(e.pos[3]; …)`; `scenario.jl` load + validate
`H > 0` + the knob. **`LIVE_FIDELITY_MODES` UNTOUCHED.** Teeth: **byte-identity when the key is
absent (the master check)**; the ceiling-factor collapse; the twin; the stage-z transient golden;
the `a_ind ∝ 1/Q` compose (K > 0).

### 3. Scenario + Godot view + four proofs (convention 14)

`scenarios/slice21_atmosphere.yaml` (K=0, cd_area=0, a CLIMBING intercept); `net/slice21_verify.gd`
(the ceiling-factor collapse as a number + the twin + held-seed bit-identical replay + the
not-a-dead-knob H tripwire); `net/slice21_ui_test.gd` (the value-guard — 16 drops the button, 17/19
show it, 18 stays 3-D, 21 = ? — **confirm at gate 3**); the `Sandbox.tscn` headless smoke-load; the
windowed shot aimed at the CLAIMED branch (the cyan ceiling falling as the missile CLIMBS).

---

## Watch-items

- **The stage-z fix is invisible to steady-state tests** — golden it (§1 above).
- **The `speed`-trap shape**: assert H MOVES the physics; "nothing threw" is not a test.
- **The miss reverses at small H** — headline the monotone-safe ceiling factor, not the miss.
- **Do NOT globally lift the "never say high altitude" caveat** — it lifts only where the key is.
- **Do NOT conflate the aero atmosphere with §11's RF "layered atmosphere/ducting"** (`propagation`).
- **`a_ind ∝ 1/Q` is a tooth, not the headline** (convention 9).
- **The engagement MUST traverse altitude** or H degenerates into slice-19's ρ knob.

## Task checklist

- [ ] Gate 0 — P1…P5 probes; the plan's numbers are all PLACEHOLDERS until this lands
- [ ] Gate 1 — `atmosphere.jl` + `test_atmosphere.jl` green
- [ ] Gate 2 — the stage-z closure + loader + knob; byte-identity + the teeth green
- [ ] Gate 3 — scenario + the four proofs; STATUS/CLAUDE/HANDOFF as-built
