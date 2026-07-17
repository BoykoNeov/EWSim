# Slice 21 — the EXPONENTIAL ATMOSPHERE `ρ(z) = ρ₀·exp(−z/H)` (§11 Tier-A)

**Status: GATE 0 RUN (findings below — they CHANGED the design). Gates 1–3 pending.** The honest completion of slices 19+20's constant-ρ
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
> **⚠ SUPERSEDED IN PART — READ "THE RUNG DECISION" BELOW.** The false-fidelity *analysis* here
> stands (and gate-0 F5/F6 MEASURED it). The **"NO RUNG" conclusion is REVERSED**: slice 21 ships
> `fidelity.atmosphere = constant | exponential`. Kept as the record of why.

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

## GATE-0 FINDINGS (9 probes — THE RECORD; read before re-proposing anything here)

Probe: `M:\claud_projects\temp\slice21_probe\` — the REAL exported aero kernels, only the
~30-line coupled tick loop local, so ρ swaps constant ↔ ρ(z) freely (convention 10: pin against
the LIVE WIRE at gates 2/3, never against this).

### F1 — "MAKE IT CLIMB" IS UNFLYABLE. The naive geometry DIED (P1/P1b/P1c)

Every steep climbing geometry misses **by kilometres under the TWIN TOO** (twin 4791 m / 8165 m
/ 4276 m). The miss is the REACH problem, not the ceiling. **The physics is a hard constraint:**
a 700 m/s missile needs ~15 s to climb 6 km, in which a head-on 800 m/s target covers 12 km — so
**"climbs a lot" and "closes fast" are MUTUALLY EXCLUSIVE.** Worse, at `z0 = 4000` the twin is
already saturating 46.6% — **that is SLICE 19's lesson (the ceiling binds), not slice 21's.**
⇒ The target must be SLOW and DISTANT (a high-altitude recon/bomber — the engagement this lesson
actually belongs to).

### F2 — ★ THE ρ(z) MISSILE TURNS EARLY, LOW, IN THICK AIR — AND THEN DOESN'T NEED TO (P1d/P1e)

With a slow distant target **everything HITS, both arms, sub-metre**, even with the ρ(z)
ceiling at **16.5 m/s² (1.7 g)** at 16 km. Why: PN does its turning EARLY (low, thick air, full
ceiling), arrives on a good collision course, and by the time it is high and cannot maneuver
**it no longer needs to.** A real insight, and it kills the naive design:
**⇒ THE LESSON REQUIRES *LATE* DEMAND, AND ONLY A MANEUVERING TARGET SUPPLIES IT.** PN nulls LOS
rate, so terminal demand against a non-maneuvering target → 0 BY CONSTRUCTION. This is structural,
not tuning.

### F3 — ★ SLICE 20's "NO MANEUVERING TARGET" RULE DOES **NOT** TRANSFER — AND MUST NOT BE COPIED

Slice 20 forbade a maneuvering target (its FINDING 7). **That rule was about attributing the
induced-drag BILL** ("the missile pays for its own turn"). **Slice 21 has K = 0: there is no
bill.** The jink here is a DEMAND SOURCE, not the lesson — and the TWIN flies the IDENTICAL
geometry against the IDENTICAL jinking target and HITS, which fully controls for it. Slice 21
**REQUIRES** what slice 20 **FORBADE**, for reasons that do not overlap. (Nor is this slice 12:
the twin proves plain PN handles this jink comfortably at sea-level density — `sat_c = 0.0%`.)

### F4 — THE SHOWCASE (P1f). Twin HITS and NEVER BINDS; ρ(z) MISSES 185×

`m(0, 1000) elev 25° v700` → `t(22000, 14000) v(−250,0,0)` jinking `a_lat = 40`:

| arm | miss | ceiling at CPA | aero_sat | α_pk | defl_sat |
|-----|-----:|---------------:|---------:|-----:|---------:|
| const ρ (TWIN) | **1.95 m** (HIT) | 133.0 | **0.0%** (never binds ONCE) | 0.085 | 0 |
| ρ(z) H = 8500  | **360.74 m** (185×) | 27.1 | 25.7% | 0.187 | 0 |

`t_cpa ≈ 43.5 s` (a long shot — ~2700 frames at `emit_every = 16`; the slice-18 verifier already
ran 2500). **H = 8500 m IS EARTH'S ACTUAL SCALE HEIGHT** — the showcase default is the real
physical value, not a tuned one.

### F5 — ★★ THE CRUX PROBE PASSES: **NO CONSTANT ρ CAN REPRODUCE IT** (P2 — the false-fidelity test)

Sweeping ρ_const ∈ [0.1, 1.225] over the identical geometry:

- **EVERY constant ρ has ceiling spread ≈ 2.03×** — *whatever its value*. That 2.03 = (700/492)²
  **is the V bleed, i.e. GRAVITY on the climb.**
- **ρ(z) has spread 8.83×.**
- A constant tuned to match the MISS (ρ* ≈ 0.42) is **crippled FROM LAUNCH** (ceiling 88 vs
  ρ(z)'s 239.5) and flies a different trajectory. **It cannot be both 269 at launch and 27 at
  intercept.** The advisor's "a single constant cannot match both ends" — **MEASURED.**

### F6 — ★★ THE SPREAD FACTORIZES **EXACTLY** — V AND z SEPARATE (P6b). SLICE 20 COULD NOT DO THIS

`a_max_aero = ½·ρ(z)·V²·S·|C_Lα|·α_max/m` ⇒ `ceiling(t)/ceiling(0) ≡ [ρ(z)/ρ(z₀)]·[V/V₀]²` —
an **IDENTITY, not an empirical fit**. Verified numerically: **residual 1.4e-17 / 0.0.**

| arm | total spread | ρ-factor | V-factor |
|-----|-------------:|---------:|---------:|
| const ρ (TWIN) | 0.494 | **1.00000 (EXACTLY)** | 0.494 |
| ρ(z) H = 8500  | 0.113 | **0.228** | 0.497 |
| ρ(z) H = 12000 | 0.172 | 0.348 | 0.493 |
| ρ(z) H = 25000 | 0.297 | 0.603 | 0.493 |

**The V-factor is ≈0.49 in EVERY arm — they all lose the same speed (gravity), so the ENTIRE
ceiling difference is ALTITUDE.** The advisor warned against an *additive* V-vs-z decomposition;
this one is **MULTIPLICATIVE and exact by construction**, so the warning is satisfied by a
stronger route than it asked for. **THE HEADLINE IS THE ρ-FACTOR** (1.000 → 0.228): pure z, no V
confound, monotone by construction. **The twin's ρ-factor is EXACTLY 1: the constant-ρ model
attributes 100% of its ceiling loss to speed. ρ(z) reveals the 4.4× it could not see.**

### F7 — ⚠ AN ADVISOR PREDICTION **REFUTED**: there is NO small-H reversal (P3)

The advisor predicted the [[ewsim-df-ellipse-sigma-monotonicity]] reversal at small H (thin air →
the missile gives up → the miss shrinks). **It does not happen.** The miss is **MONOTONE
DECREASING in H across the entire sweep**: 6821 m (H=2000) → 360.74 (8500) → 3.81 (40000) → the
twin's 1.95 as H→∞. **The mechanism is the difference:** slice 20's reversal came from **SPEED
loss** (a bled-out missile stops trying and coasts into a close pass). **Thin air costs ZERO
speed here (K=0, cd=0) — it costs only AUTHORITY.** The missile flies fast and straight, right
past the target. *(A 4 m blip at H 10000→12000 is near-hit frame-sampling noise, not a reversal.)*

### F8 — THE LEAK IS THE BINDING CONSTRAINT (P6a) ⇒ **H ∈ [6000, 25000]**, MEASURED

slice-19 FINDING 14's ceiling leak (α_max bounds the COMMAND; lift uses the ACHIEVED α):

| H | 2000 | 2500 | **3000** | 3500 | 5000 | **6000** | 8500 | 25000 |
|---|-----:|-----:|-----:|-----:|-----:|-----:|-----:|-----:|
| α_pk (α_max = 0.2) | 0.2013 | 0.2006 | **0.2000** | 0.1993 | 0.1964 | **0.1940** | 0.1867 | 0.1215 |
| | ★LEAK | ★LEAK | ★LEAK | ok | ok | ok | ok | ok |

**Leak boundary H = 3000 ⇒ floor 6000 (a 2× margin — the slice-20 K discipline).** `defl_sat == 0`
EVERYWHERE (the fourth cap provably not standing in). Miss reads BOTH ways from the 8500 default:
**6000 → 1706 m, 8500 → 360.74 m, 25000 → 6.29 m (a hit).**

### F9 — THE STAGE-z FIX IS INVISIBLE TO STEADY-STATE TESTS (P5) — GOLDEN IT

Entry-z vs stage-z: `max|Δz| = 0.77 m` over 90 s; **the miss moves 0.136 m on a 360 m lesson
(0.04%)**. Exactly slice-17's entry-θ shape (0.019 m / 8 s). **No steady-state test can catch it.**

### F10 — THE COMPOSE IS REAL BUT MODEST (P6c) ⇒ CLOSED-FORM TOOTH, NOT A SCENARIO DIFF

At K = 0.15 the ρ(z) arm's peak induced bill is 26.97 vs the twin's 20.29 (+33%). Real, but the
trajectories differ so a scenario diff is confounded. **Ship it as a CLOSED-FORM unit test**
(`|a_ind| = K·m·a_perp²/(Q·S)`: same `a_perp`, two Q's ⇒ bill ratio ≡ Q₁/Q₂), not a wire number.

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

## ★ THE RUNG DECISION — `fidelity.atmosphere = constant | exponential` (SETTLED, advisor)

**Gate 0 exposed a hole in the no-rung plan; the advisor then knocked the plan's own principle
down. SLICE 21 SHIPS A RUNG.** This reverses §3's conclusion. The record:

**What gate 0 found (the hole).** The slice-20 precedent is *"a rung must name physics the knob
cannot express — and `:free` IS `K = 0`."* That works for slice 20 because **`K = 0` is a legal,
exact, IN-DOMAIN slider position (the minimum).** **For H it is FALSE:** constant ρ is `H = ∞` —
**a limit point, not a slider position. NO finite H produces it** (within 1% at z = 14 km needs
`H ≈ 1.4e6`). And `set_param` sets a value, **it cannot REMOVE a key** ⇒ the twin was not
reachable on the live wire at all.

**Why the fallback ("no rung; the twin moves into `test_missile.jl`") was WRONG — the advisor's
catch, and it is decisive.** The plan's reason to refuse the rung was *"`:constant` names no
physics ρ(z) lacks; it names the ABSENCE of a gradient."* **That is word-for-word the description
of `:airframe = point_mass` ("no α→lift coupling") and `:propagation = free_space` ("no
terrain").** The suite already expresses "the absence of the new physics" as a rung, **twice**.
**Applied consistently the principle DELETES those two rungs — so it cannot be the discriminator.**

**THE DISCRIMINATOR THE SUITE ACTUALLY USES — write this down, it is the general result:**

> **Is the off-state (a) a DISTINCT CODE PATH and (b) NOT KNOB-REACHABLE?**
> - **KNOB** (`af_cma`, `af_k_induced`): the off-state is an **in-domain slider value** (0),
>   continuous, **no separate path**.
> - **RUNG** (`:airframe`, `:propagation`, **`:atmosphere`**): the off-state is a **distinct code
>   path** and is **not reachable by any knob value**.

Slice 21's constant-ρ is a distinct code path (**the two-closure key-gate — the plan's own design
decision 4**) **AND** not knob-reachable. **Both criteria say RUNG.** Slice 20's no-rung rested on
two legs that BOTH fail here: (a) `K = 0` is the slider minimum — `H = ∞` is not; (b) slice 20's
lesson was CONTINUOUS so a button would hide it — **here the punchline IS the binary**.

**The benefit was MIS-SCOPED (the plan filed it under "verifier convenience" — it is not).**
HANDOFF frames this slice as **the honest completion of the constant-ρ approximation**: the whole
lesson is *"constant-ρ was LYING TO YOU at altitude."* **The live side-by-side IS the punchline** —
flip to the old model → **HIT (1.95 m)**, flip to the real atmosphere → **MISS (360.74 m)**.
Knob-only **cannot reach the old model** (H-max misses by 6.29 m, not 1.95), so it buries the
punchline in a Julia unit test and promotes *"dial the planet's scale height"* — pedagogically
weird, and flagged as such — to the headline.

**THE CONSTRUCTION IS CHEAP — SLICE 17's EXACT STRUCTURE:**
```
haskey(c, :af_scale_height) && get(w.fidelity, :atmosphere, :constant) === :exponential
```
The **verbatim slice-19/20 else-arm then serves BOTH key-absent AND `:atmosphere === :constant`**,
so **byte-identity is automatic** and the three-state wrinkle dissolves. `ATMOSPHERE_MODES` lives
in `atmosphere.jl` (included **before `radar.jl`** — convention 1/7, referenced ONCE by
`LIVE_FIDELITY_MODES` and `set_fidelity`). **H stays a SEVERITY KNOB, read only on the
`:exponential` arm.** Class **4c**, live-settable, **NO `set_fidelity` guard** — identical to
`:airframe`.

**CONVENTION-9 CONSEQUENCE (settled in the same breath): `:atmosphere` is the scenario's ONE
toggled button.** `:airframe` is **AUTHORED FIXED at `pitch_coupled`** (the missile must stay
coupled for a ceiling to exist at all). For slice 21 the contrast that matters is
**constant-vs-ρ(z)**, NOT slice-19's point_mass-vs-coupled. **One button, not two.**

**⚠ THIS KILLS DESIGN DECISION 8 ("zero client code").** The client's `_setup_spatial_fid_btn`
checks the **airframe branch FIRST**, value-guarded on `_fidelity.has("airframe")` — and slice
21's scenario HAS `airframe: pitch_coupled` in its fidelity block, so the client would show the
**airframe** cycler instead of the **atmosphere** one. **This is the slice-16 client note
recurring** ("value-guard it when a later slice adds a fidelity alongside"). Gate 3 must route the
shared button to `:atmosphere` when present. **NOT zero client code.**

---

## ⚠ THE OPEN QUESTION GATE 0 EXPOSED — THE TWIN IS NOT LIVE-REACHABLE
> **RESOLVED — see "THE RUNG DECISION" above. The rung makes the twin a live arm (the button).**
> Kept as the record of how the problem was found.

**The no-rung argument has a hole the slice-20 precedent does not cover, and it is worth stating
precisely because it cuts against the planned framing (§3 above).**

The precedent test is *"a rung must name physics the knob cannot express — and `:free` IS
`K = 0`."* That works for slice 20 because **`K = 0` is a legal, exact, IN-DOMAIN slider position
(the minimum).** The knob genuinely expresses the OFF state.

**For H it is FALSE.** Constant ρ is `H = ∞` — **a limit point, not a slider position. NO finite H
produces it.** To get within 1% of constant at z = 14 km needs `H ≈ 1.4e6 m` — the slider would
span six orders of magnitude. So the sentence "the knob already expresses that state" is
**not true here**, and with it goes the direct slice-20 analogy.

**The practical consequence:** `set_param` sets a value; **it cannot REMOVE a key.** So the
constant-ρ twin **cannot be an arm of the live wire** the way slice-20's `K = 0` and slice-19's
`:point_mass` could. A Godot verifier drives ONE server (one scenario) — it has no way to reach it.

**The resolution taken (pending advisor):** keep **NO RUNG**, and put the twin where it actually
belongs — **`test_missile.jl`, not the wire**:
- **The TEST owns the twin** (Julia constructs both worlds freely): key-absent ⇒ **byte-identical
  to slices 19/20** (the master check), plus the F5 "no constant matches the spread" tooth and the
  F6 exact factorization. This is where byte-identity lives anyway.
- **The WIRE owns the KNOB**: the lesson reads off the H slider, which spans hit → catastrophic
  miss (25000 → 6.29 m; 8500 = Earth → 360.74 m; 6000 → 1706 m) and whose **ρ-factor headline is
  monotone across the whole range** (F6/F7).
- The `:airframe` button stays THE toggled fidelity (convention 9), as slice 19/20's reference arm.

**Why not just add the rung?** It would buy a live constant-ρ arm — but `:constant` names no
physics ρ(z) lacks; it names the *absence* of a gradient, which is the OLD model, and the whole
suite already gates old models on key presence (`af_cma`, `af_k_induced`). Adding a rung to make a
verifier's life easier is a **test-convenience argument, not a physics one**, and `LIVE_FIDELITY_MODES`
should not grow on that basis. **But the honest note stands: the slice-20 precedent does NOT
license the no-rung call here — it has to stand on its own feet, and the argument above is the one
it stands on.**

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
3. **A NEW RUNG `fidelity.atmosphere = constant | exponential` (`ATMOSPHERE_MODES`), PLUS the
   severity knob `af_scale_height` (H, m).** See "THE RUNG DECISION" — the off-state is a distinct
   code path AND not knob-reachable, so both of the suite's rung criteria are met. The rung is
   THE BUTTON (the live old-model-HITS vs truth-MISSES side-by-side = the punchline); H is the
   severity slider on the `:exponential` arm only. `LIVE_FIDELITY_MODES` GAINS `atmosphere`.
4. **TWO CLOSURES, gated on `haskey(c, :af_scale_height) && get(w.fidelity, :atmosphere,
   :constant) === :exponential`; the else-arm is slice 17/19/20 TEXTUALLY VERBATIM** — and it
   therefore serves BOTH key-absent AND `:constant`, so byte-identity is automatic. Do NOT
   compute `ρ_stage` unconditionally and lean on `exp(0)==1` — the
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
8. **Client: NOT zero code** (design decision 8 as first planned is DEAD — see the rung decision).
   Slice 19's aero strip carries the ceiling plot unchanged, but the shared button must route to
   the `:atmosphere` cycler even though `_fidelity.has("airframe")` is TRUE (the airframe branch
   is checked FIRST — the slice-16 client note recurring).

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

`air_density(z; rho0, H)` + `const ATMOSPHERE_MODES = (:constant, :exponential)`. Closed-form
teeth: the z=0 identity (`== rho0`, bit-exact); the one-scale-height point (`ρ(H)/ρ₀ == exp(-1)`);
the H→∞ limit ⇒ `== rho0` bit-exact; the negative-z floor (convention 6); monotone-decreasing in z.
**Included BEFORE `radar.jl`** (convention 1 — it carries a mode-const `LIVE_FIDELITY_MODES` must
reference ONCE; convention 7's one-list-no-drift).

### 2. Wired — the rung + stage-z in the coupled closure + the loader key

The two-closure gate (key AND rung); the per-stage params rebuild; ρ(z) at the decide!/telemetry
sites (missile.jl ~272, ~320, ~637–645) via `air_density(e.pos[3]; …)` — **each rung-gated too**;
`scenario.jl` load + validate `H > 0` + the knob; **`LIVE_FIDELITY_MODES` GAINS
`atmosphere = ATMOSPHERE_MODES`** (the ONLY plumbing edit; NO `set_fidelity` guard — the
`:airframe` precedent). Teeth: **byte-identity for BOTH key-absent AND `:constant` (the master
check)**; the F6 exact factorization (ρ-factor × V-factor, and the `:constant` arm's ρ-factor is
**EXACTLY 1**); the F5 "no constant matches the spread" control; the **stage-z transient golden**
(F9 — 0.136 m on a 360 m lesson: nothing else can catch it); the closed-form `a_ind ∝ 1/Q` compose
(F10).

### 3. Scenario + Godot view + four proofs (convention 14)

`scenarios/slice21_atmosphere.yaml` (K=0, cd_area=0, `airframe: pitch_coupled` AUTHORED FIXED,
`atmosphere` THE button, a jinking high-altitude target — F3/F4); `net/slice21_verify.gd` (the
ρ-factor collapse as a number + **the live twin across the rung toggle** (1.95 vs 360.74) +
held-seed bit-identical replay + the not-a-dead-knob H tripwire); `net/slice21_ui_test.gd` (the
value-guard, now FIVE ways — 16 drops the button, 17/19 show `airframe`, 18 stays 3-D, **21 must
show `atmosphere` DESPITE `_fidelity.has("airframe")` being true**); the `Sandbox.tscn` headless
smoke-load; the windowed shot aimed at the CLAIMED branch (the cyan ceiling falling as the missile
CLIMBS, demand crossing it, AERO SAT lit).

---

## Watch-items

- **The stage-z fix is invisible to steady-state tests** (F9: 0.136 m on a 360 m lesson) — only a
  TRANSIENT GOLDEN catches it. Read the STAGE `P[3]`, never the entry pos.
- **The `speed`-trap shape**: assert H MOVES the physics; "nothing threw" is not a test.
- **The miss does NOT reverse in H** (F7 — an advisor prediction REFUTED; thin air costs
  AUTHORITY, not SPEED). Headline the ρ-factor anyway: it is monotone BY CONSTRUCTION.
- **The α LEAK bounds H at 6000** (F8) — a breach means lift exceeds the ceiling and the lesson
  erodes. `k_alpha`/`k_q` are NEVER knobs (slice-19 FINDING 14).
- **Do NOT globally lift the "never say high altitude" caveat** — it lifts ONLY on the
  `:exponential` arm of a scenario carrying the key. Slices 19/20's wires keep the old language.
- **Do NOT conflate the aero atmosphere with §11's RF "layered atmosphere/ducting"** (`propagation`).
- **`a_ind ∝ 1/Q` is a closed-form tooth, not the headline** (convention 9 + F10's confound).
- **The engagement MUST traverse altitude** or H degenerates into slice-19's ρ knob.
- **⚠ THE SHOWCASE SITS IN A WINDOW (advisor, for gates 2/3):** `a_lat = 40` works but **60 makes
  the TWIN miss too** and **`tvx = −400` breaks both arms** (F1's reach wall). **Pin the
  robustness margin the way H was bounded** — a showcase one step from collapsing is not pinned.
- **The client button is NOT free** — the airframe branch is checked first and slice 21's fidelity
  block HAS `airframe`. Route to `:atmosphere`; re-smoke 16/17/18/19/20.

## Task checklist

- [x] Gate 0 — **DONE, 9 probes (F1–F10). The design changed in three places; the rung was
      REVERSED IN.** Remaining: pin the showcase's robustness window (advisor flag).
- [ ] Gate 1 — `atmosphere.jl` (+ `ATMOSPHERE_MODES`) + `test_atmosphere.jl` green
- [ ] Gate 2 — the rung + stage-z closure + loader + knob; byte-identity (key-absent AND
      `:constant`) + the F5/F6/F9/F10 teeth green
- [ ] Gate 3 — scenario + the four proofs + the client button routing; STATUS/CLAUDE/HANDOFF as-built
