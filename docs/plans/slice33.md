# Slice 33 — THE RING IS AN FOV BUDGET ITEM: WHAT THE PARASITIC LOOP COSTS YOU IS THE ENVELOPE (§11 Tier-A)

The ELEVENTH slice of the bank-to-turn / 3-D arc (23 = the 6-DOF substrate + skid-to-turn, 24 =
bank-to-turn + roll-lag, 25 = a seeker in the 6-DOF loop, 26 = the radome parasitic loop, 27 = the
compensation autopilot, 28 = the slope CURVE, 29 = the SCHEDULED compensator, 30 = the ENVELOPE and
the one-sided constraint, 31 = an imperfect gyro, 32 = the seeker's field of view), and the
successor slice 32 itself nominated:

> *"**THE GIMBAL ON THE RADOME WIRE** — measured here (§ the corollary), kept off the showcase by
> convention 9. **The strongest successor: it is the first mechanism in the arc that turns slice
> 26's ring into a LOCK LOSS.**"* — `docs/plans/slice32.md`, Deferred (NAMED)

**Status: COMPLETE (2026-07-29, suite 6028 → 6215). Gate 0 = 4 probes; the advisor's opening
hypothesis was REFUTED by probe 1 and the live claim was found in a DIFFERENT CURRENCY by probes
2–4 (§0). Gate 1 = the kernel, shipped by REDEFINING the predicate from it (§1). Gate 2 = the
readout, the wired lesson, and the loader composition (§2). Gate 3 = the wire, the client's
COMPOSITION branch, and the four proofs (§3). Probe scripts in `M:\claud_projects\temp\slice33\`;
the full as-built ledger is in `docs/STATUS.md`.**

⚠ **THE DEFERRAL'S NAME IS LOOSE AND THE PLAN DOES NOT INHERIT IT.** Its § points at slice 32's
FOV × radome corollary, not at head state. A REAL GIMBAL — a head with its own state, servo
bandwidth, rate limit and mechanical stop — is a **separate and bigger slice**, and `frames.jl`
(~line 691) says so in terms: it *"adds a dynamical state AND it rewrites 26–31's `look_az` (the
bend would key off the HEAD-vs-body angle rather than the LOS-vs-body angle)"*. This slice stays
**STRAPDOWN**. The gimbal is re-banked below, with the lesson it should carry.

---

## The one-paragraph statement of the lesson

Slice 32 asked what field of view a seeker needs and answered with the ENGAGEMENT: the collision
triangle's own lead angle, `V_m·sin λ = V_t·sin θ`, which on its wire is 18.13°. **That is the
QUIET-GLASS answer.** Slices 26–31 spent six slices on a missile that shakes itself — and every one
of them recorded, as a standing fact, that *the ringing arm still hits*: slice 26 wrote "**the MISS
is NOT the metric** — the ringing arm STILL HITS (2.18 m)", and 27–31 each inherited it, which is
why the whole family measures `rms q` / `rms r` instead. It is true here too, everywhere: across
three glass depths and the full R̂ ladder, **not one ringing arm misses by more than 3.53 m**. The
ring was benign *because the seeker had an infinite window*. Give it a real one and the same ring —
same glass, same R̂, same seed — misses by **one to four kilometres**, because the excursion the
limit cycle adds to the look angle is spent out of the very budget slice 32 measured. **The FOV a
seeker needs is the engagement's lead PLUS the parasitic loop's excursion**, and the second term is
continuous and monotone in the ring's amplitude: 18.14° → 20.62° → 22.12° → 23.92° → 25.01° as `R̂`
walks from slice 30's design rule to slice 28's boresight characterization.

> **THE LESSON, IN ONE SENTENCE.** A limit cycle you were told to measure in rad/s is spent in
> DEGREES OF FIELD OF VIEW — the ring costs you not accuracy but the ENVELOPE, and slice 30's
> scalar buys the whole envelope back.

⭐⭐ **THE PAYLOAD IS THAT SLICE 30's RULE IS AN ENVELOPE RULE, NOT ONLY A STABILITY RULE.** Slice 30
shipped `radome_slope_worst` as the aim point that makes a scalar compensator unconditionally
stable. Aim `R̂` there and the FOV requirement returns to **18.14°** — the radome-free engagement's
own 18.13°, to within the missile's aerodynamic incidence — and it does so at A = −0.10, −0.15 AND
−0.20, i.e. **depth-independently**. The glass gets worse, the requirement does not move.

---

## §0 — Gate 0 (4 probes, 2026-07-28)

⚠⚠ **THE ADVISOR'S OPENING HYPOTHESIS WAS REFUTED, AND THE REFUTATION IS LOAD-BEARING** — it is the
reason this slice does NOT claim to invert slice 32's closing sentence. The hypothesis was that the
band between slice 32's two measured endpoints (`R̂ = R₀`, rings, 72 % out; `R̂ = radome_slope_worst`,
0.00 % out) might contain a *marginally* stable design whose look excursion is nonetheless past the
window — the first regime where the FOV bound binds BEFORE the stability bound.

**PROBE 1 killed it in its own currency.** The stability onset and the FOV break arrive at the SAME
`R̂` bracket — quiet at −0.27 (rms r 0.031, 0.000 % out), ringing at −0.24 (rms r **0.70983**, 37.6 %
out) — which reproduces slice 30's measured boundary to the digit (its "last decisive ring
−0.24/0.709"). ⇒ **slice 32's "the FOV bound is NOT tighter than the stability bound on this glass"
STANDS, and this slice must not be written as overturning it.** What slice 33 changes is that the
FOV *requirement* becomes a CONTINUOUS function of the residual where slice 32 had a single number.

⚠⚠ **THE ISOLATION, BAKED IN FROM THE FIRST RUN (advisor, before any probe): `rms r` IS NOT A
STABILITY READ ON A WINDOWED ARM.** Slice 32 already warned that the metric inverts — losing the
measurement CUTS the parasitic feed, so `rms r` FALLS while the miss OPENS — so a low `rms r` on a
windowed arm is indistinguishable between "this design is stable" and "the seeker lost lock and
stopped driving the loop". **Every `R̂` is therefore flown TWICE**: a FREE arm (no `seeker_fov_deg`
key at all) supplies the stability read and the excursion, and a WINDOWED arm at the SAME `R̂`
supplies the envelope read. This is not a probe convenience; it is the shipped discipline (§ the
seam).

### P1 — the band between slice 32's endpoints (`p1_rhat_band.jl`)

Glass R₀ = −0.03, A = −0.15 (⇒ `radome_slope_worst` = −0.33), vy = 200, fov = 20°.

| R̂ | FREE: rms r | FREE: excursion | FREE: miss | WINDOWED fov 20: miss | out % | t_break |
|---|---|---|---|---|---|---|
| −0.33 | 0.05879 | 18.14° | 0.184 m | 0.184 m | 0.000 | — |
| −0.30 | 0.04716 | 18.14° | 0.030 m | 0.030 m | 0.000 | — |
| −0.27 | 0.03070 | 18.14° | 0.114 m | 0.114 m | 0.000 | — |
| −0.24 | 0.70983 | 20.62° | 1.450 m | **936.312 m** | 37.620 | 6.632 |
| −0.21 | 0.85201 | 21.49° | 1.157 m | 2007.964 m | 43.261 | 5.141 |
| −0.18 | 0.93194 | 22.12° | 0.920 m | 2567.950 m | 44.736 | 4.421 |
| −0.15 | 0.99779 | 22.83° | 1.722 m | 2870.788 m | 49.034 | 3.852 |
| −0.12 | 1.03165 | 23.34° | 1.163 m | 3193.596 m | 62.783 | 2.809 |
| −0.09 | 1.05848 | 23.92° | 1.819 m | 3468.112 m | 65.869 | 2.426 |
| −0.06 | 1.07490 | 24.50° | 0.754 m | 3640.996 m | 69.271 | 2.117 |
| −0.03 | 1.07211 | 25.01° | 2.070 m | 3759.992 m | 72.226 | 1.883 |

Reference (no glass at all): rms r 0.01589, excursion 18.13°, miss 0.191 m, 0.000 % out at fov 20.

⭐ **THE FREE-MISS COLUMN IS THE SLICE.** Every ringing arm HITS (0.75–2.07 m) — the arc's standing
fact since 26 — and the SAME arm with a 20° window misses by 0.9–3.8 km.

### P2 — the predicate (`p2_fov_budget.jl`)

The critical FOV (smallest window that HOLDS: 0.000 % out AND miss < 10 m) against the excursion
measured on the FREE arm. Verdicts were monotone in `fov` in every row — a clean step, no
re-entrant cells.

| R̂ | rms r | excursion | critical fov | ⌈excursion⌉ |
|---|---|---|---|---|
| −0.33 | 0.05879 | 18.14° | 19° | 19 |
| −0.24 | 0.70983 | 20.62° | 21° | 21 |
| −0.18 | 0.93194 | 22.12° | 23° | 23 |
| −0.09 | 1.05848 | 23.92° | 24° | 24 |
| −0.03 | 1.07211 | 25.01° | 26° | 26 |

⭐ **AND THE TWO SIDES COME FROM DIFFERENT CODE PATHS ON DIFFERENT RUNS**, which is what makes it a
MEASUREMENT and not a restatement (slice 32's `collision_lead_angle` vs `seeker_in_fov` precedent):
the excursion is `boresight_angle(att, û_tru)` accumulated on an arm with **no `seeker_fov_deg` key
at all**, while `held` is the shipped `seeker_in_fov` verdict inside `_observe_point3d!`.

### P3 — causation and robustness (`p3_causation.jl`)

**(a) The ring's AMPLITUDE is the budget item — not the value of `R̂`.** `af_alpha_max` is slice
26's own instrument for exactly this: it grows the limit cycle's amplitude while leaving its onset
where it was ("the ceiling BOUNDS the cycle, the radome decides whether there IS one"). At **FIXED**
R̂ = −0.18 and **FIXED** glass:

| α_max | rms r | excursion | free miss | critical fov |
|---|---|---|---|---|
| 0.20 | 0.67256 | 20.67° | 1.842 m | 21° |
| 0.30 | 0.93194 | 22.12° | 0.920 m | 23° |
| 0.45 | 1.16949 | 23.70° | 0.746 m | 24° |
| 0.60 | 1.31490 | 24.30° | 0.441 m | 25° |

⚠ **α_max IS A CAUSATION PROBE AND MUST NOT BECOME A SLIDER** — it is a confounded lever (slice 20
disqualified it for the induced-drag bill) and the shipped wire HOLDS it (advisor; § convention 9).

**(b) Robustness — three glass depths, and the cure is depth-independent.**

| A | R̂ | rms r | excursion | free miss | critical fov |
|---|---|---|---|---|---|
| −0.10 | **−0.230** (slice 30's rule) | 0.02550 | **18.14°** | 0.139 m | 19° |
| −0.10 | −0.120 | 0.94087 | 21.93° | 0.349 m | 22° |
| −0.10 | −0.030 | 1.09301 | 24.31° | 0.238 m | 25° |
| −0.15 | **−0.330** (slice 30's rule) | 0.05879 | **18.14°** | 0.184 m | 19° |
| −0.15 | −0.120 | 1.03165 | 23.34° | 1.163 m | 24° |
| −0.15 | −0.030 | 1.07211 | 25.01° | 2.070 m | 26° |
| −0.20 | **−0.430** (slice 30's rule) | 0.08903 | **18.14°** | 0.579 m | 19° |
| −0.20 | −0.120 | 1.04638 | 24.16° | 2.131 m | 25° |
| −0.20 | −0.030 | 1.08561 | 25.55° | 3.528 m | 26° |

⭐⭐ **THE THREE BOLD ROWS ARE THE PAYLOAD.** Slice 30's aim point returns the requirement to 18.14°
at every depth — the radome-free engagement's own number.

**16 of 16 cells** across three independent axes (the R̂ ladder, an α_max amplitude sweep at fixed
R̂, three glass depths) satisfy `critical fov == ⌈excursion⌉`.

### P4 — cliff, or a survivable band? (`p4_transition.jl`)

The integer grid resolves the transition only to ±1°. At 0.25°:

| R̂ = −0.18, excursion 22.124° | | | R̂ = −0.03, excursion 25.011° | | |
|---|---|---|---|---|---|
| fov | out % | miss | fov | out % | miss |
| 21.50 | 42.42 | 1609.457 m | 24.50 | 61.34 | 2642.941 m |
| 21.75 | 41.46 | 998.585 m | 24.75 | 59.11 | 1819.179 m |
| **22.00** | **3.21** | **31.899 m** | **25.00** | **0.10** | **2.002 m** |
| 22.25 | 0.00 | 0.920 m | 25.25 | 0.00 | 2.070 m |

⭐ **A SURVIVABLE BAND EXISTS AND IT IS NARROW — about 0.4° wide.** At R̂ = −0.03 a window
**0.011° BELOW** the excursion loses lock for 0.10 % of the approach and still HITS (2.002 m, within
0.07 m of the free arm's 2.070) — slice 32's re-acquisition evidence, reproduced. 0.12° below →
31.9 m. 0.37° below → 998 m. Then kilometres.

⭐⭐ **AND `t_break` IS THE DISCRIMINATOR — SLICE 32's OWN MECHANISM IN A NEW AXIS.** Every
held-or-survived cell breaks at **t ≈ 10.3–10.4 s** (near CPA); every lost cell breaks at
**t = 1.9–6.2 s**, while the lead is still building. Slice 32: *"A short loss is survivable; what is
terminal is a loss while the lead is still building."* Here the same sentence is reached by moving
the WINDOW instead of the crossing speed.

---

## §1 — Gate 1 (COMPLETE, 2026-07-28 — 6028 → 6062)

**ONE kernel, in `frames.jl` beside slice 32's three:**

```julia
seeker_fov_margin(att, los, fov) = max(Float64(fov), 0.0) - boresight_angle(att, los)
seeker_in_fov(att, los, fov)     = seeker_fov_margin(att, los, fov) ≥ 0.0     # ← REDEFINED
```

⭐ **THE REDEFINITION IS THE GATE, NOT THE ADDITION** (advisor, before any code). Shipping the
margin *beside* the predicate and wiring it at gate 2 would leave gate 1 with a kernel nothing
calls — which is precisely the arrangement **slice 32's own gate 1 rejected one layer up** ("the
gate-0 seam computed `hypot(fa,fe) ≤ fov` INLINE, so kernels shipped beside it would have had
`test_frames.jl` prove a SECOND implementation and nothing about what flies"). Defining the
predicate FROM the margin puts the shipped number on the flying path with **zero seam edits** —
`missile.jl:1670` still calls `seeker_in_fov` — and leaves exactly ONE comparison site and ONE
clamp site. The clamp-ownership claim RELOCATED from `seeker_in_fov`'s docstring rather than being
duplicated there.

⚠ **AND THAT MAKES THE OBVIOUS TEST VACUOUS.** `(margin ≥ 0) == seeker_in_fov(...)` is now `x == x`
(convention 11's tautology), so it is NOT shipped. The tooth is the subtraction form against **the
comparison form written longhand** — the expression slice 32 shipped, `boresight_angle ≤
max(fov,0)` — **swept at the boundary**, because that is the only place a subtraction could diverge
from a comparison: 600 seeded `(att, los)` × 10 near-boundary windows (`b`, `prevfloat(b)`,
`nextfloat(b)`, `b·(1∓1e−15)`, `b∓1e−12`, `0.5b`, `2b`, `−b`) = **6000 cells, 0 mismatches, no
tolerance anywhere**, landing 3000/3000 on the two sides. The underlying fact is about IEEE doubles
and not about the algebra — two distinct finite doubles never subtract to zero, and rounding to
nearest preserves sign — which is what licenses the refactor at all; it is PINNED by that sweep,
not asserted in a comment. `x − x` is EXACTLY `+0.0` (600/600) and one ULP tighter is STRICTLY
negative (600/600), so slice 32's `prevfloat` boundary tooth is inherited intact.

⚠⚠ **THE DIVERGENCE THE ADVISOR CAUGHT, AND IT FLIPS A VERDICT — NOT JUST A MAGNITUDE.** The wire
ships `seeker_fov_deg` **AUTHORED** (slice 32: a HUD showing 0° for a negative slider would hide
what the student is holding), while the margin must use the **CLAMPED** window or its sign stops
agreeing with the predicate — which is the entire reason it exists. ⇒ **the shipped keys do not
reconstruct this one on a negative slider**, and a client deriving `fov − look_angle` disagrees
with the core. It is not merely a magnitude gap (−20° vs −25° at `fov = −5°`, `b = 20°`): it flips
the verdict on **exactly the LOS the never-locked state is defined by** — an on-boresight target is
IN a `fov = −1` window (only that one is), where the subtraction says OUT. Written into the kernel
docstring and pinned with a PAIRED agree-at-positive-`fov` case.

Also new: `NaN` in the predicate's degenerate table (a claim about `max`, which PROPAGATES — a
`max` written the other way round would admit everything); strict monotonicity in `fov` above the
clamp and flatness below it (what makes "widen the seeker" a one-slider cure with a well-posed
**bracket**, seam discipline 2); the exact-degree PAIRED polarity case (20° LOS: +5° inside a 25°
window, −5° against a 15° one).

**BEHAVIOUR-PRESERVING, PROVEN ON THE WIRE — not by reading the diff.** The predicate is provably
the same boolean, but this project's discipline is to measure it:

* **§0's P1 table reproduces CELL FOR CELL** — all 11 R̂ rows in both arms, plus the reference
  (0.01589 / 18.13° / 0.191 m). Spot: −0.24 → free rms r 0.70983, excursion 20.62°, free miss
  1.450 m; windowed 936.312 m, 37.620 % out, `t_break` 6.632. −0.03 → 1.07211 / 25.01° / 2.070 m;
  3759.992 m, 72.226 %, 1.883.
* **Slice 32's four showcase arms reproduce to the digit** — 1140.63505 / 0.16777 / 0.06197 /
  0.16777 m, ToF 15.40 / 15.31 / 12.93 s (its own gate-1 commit's numbers), `look_max` 103.14 /
  29.02 / 23.86 / 29.02°.
  ⚠ **THAT CLAIM COVERS MISS / ToF / `look_max` AND NOT THE `out%` COLUMN, WHICH IS DEAD** (advisor):
  `slice32/g1_wire_check.jl` read `comp[:seek_in_fov]` — the key **slice 32's own gate 2 removed**,
  as its stale-readout catch — so it defaulted to `true` and printed `0.0 %` on all four arms where
  slice 32 measured 67.98 %. A column that reproduces because it counts nothing is not a
  reproduction ("a number that does not print is not a proof", slice 21). ⭐ **FIXED to read the
  shipped `seeker_valid` telemetry, and the column then reproduces slice 32's own gate-1 number
  EXACTLY: 69.6 % / 0.0 / 0.0 / 0.0** — so the claim now covers all four columns, but it did so only
  after the dead one was found. P1's `out%` reads that same key and reproduces independently
  (37.620 / 43.261 / 44.736 / 49.034 / 62.783 / 65.869 / 69.271 / 72.226).
* Full suite green, **6028 → 6062**.

⭐ **AND THE RUN CONFIRMED THE SEAM DISCIPLINE'S PREMISE AS A NUMBER**: the windowed arms'
`look_max` column reads **96.29 / 90.95 / 89.42 / 89.27 / 90.32 / 90.08 / 90.14 / 90.40°** across
every broken cell — the post-lock-loss runaway, ~90° regardless of a ring whose actual excursion
was 20.62–25.01°. **The predictor and the predicted must not come from the same run**, and that is
now measured rather than argued (docstring; enforced by the verifier's structure at gate 3).

**What gate 1 deliberately does NOT own** (advisor's checklist): no `ceil` / `critical_fov` helper
(seam item 2 — it would pin the 1° measuring grid); no excursion or running-peak accumulator (peak
-hold is DISPLAY state, settled at slice 27); no telemetry key (gate 2); no knob and no rung (both
sliders already ship); and no proof that `critical fov == excursion` — that needs a wire, exactly
as slice 32's gate 1 deferred `look == lead`. **Seam item 1 is a DOCSTRING deliverable at gate 1,
not a test**: a pure kernel cannot exercise a two-run discipline, and manufacturing a test for it
would be a fake tooth.

⚠ **THE CLAMP CHANGED OWNER, AND THIS CODEBASE REPEATS THAT FACT DELIBERATELY** (advisor). The
seam comment at `missile.jl:1652` and the test comment at `test_frames.jl:907` both named
`seeker_in_fov` as the single clamp site; after the redefinition it DELEGATES and does not clamp,
so both were REWORDED (the seam's "deliberately NOT clamping twice" stays true and unchanged — the
edit is a reword, not a behaviour note). ⚠ `docs/STATUS.md:4284` says it too, inside **slice 32's
dated as-built entry**, and is deliberately LEFT ALONE: it records what slice 32 shipped, and
rewriting a per-slice ledger entry to match a later slice would make the ledger stop being a
history. **Gate 3's STATUS entry must state the relocation** — this line is the carry-forward.

**Carried into gate 2:** ship `<sid>.seeker_fov_margin_deg` under `_fov_on` with **`_finite_coord`,
never `_finite`** (the margin goes hugely negative on the never-locked side, and `_finite` clamps
only the upper bound — the slice-29 `k̂` catch, which slice 32's own comment at `missile.jl:2111`
already names); decide whether the seam hoists one margin local or telemetry calls the kernel again
(three `boresight_angle` calls/tick is nothing at 27k ticks/s, and hoisting risks ambiguity about
which kernel flies); and the byte-identity re-run of the 26–32 verifiers.

---

## §2 — Gate 2 (COMPLETE, 2026-07-29 — 6062 → 6169)

Gate 1 put the margin on the flying path with no seam edit; **gate 2 gave it the two ends it did
not have — a READOUT and a WIRED LESSON** — and pinned the composition as numbers in
`test_missile.jl` (eight testsets, +107).

### The seam — ONE line, and the kernel is called AGAIN rather than hoisted

```julia
tel["$sid.seeker_fov_margin_deg"] =
    _finite_coord(rad2deg(seeker_fov_margin(c[:att_q]::Quat, û_tru, fov_rad)))
```

The plan left the hoist-vs-recall question open; **it is RECALL** (advisor). `look_angle` on the
line above already has exactly that posture, and it keeps **ONE flying comparison site**
(`seeker_in_fov`, `missile.jl:1673`) instead of creating an ambiguity about which kernel flies —
three `boresight_angle` calls a tick is nothing at 27k ticks/s. Same `att`, same `û_tru`, same
`fov_rad` ⇒ the shipped sign and the flying verdict are the **same bits**, not two opinions.

⚠ **AND THE `fov_rad` SEAM COMMENT NEEDED A REWORD, FOR THE SECOND TIME IN TWO GATES.** It said
flatly "gate-2 telemetry must read `c[:seeker_fov_deg]`, never this local". That is right for the
DEGREES key (authored value; this local is radians AND the wrong number on a negative slider) and
WRONG as a blanket rule — the margin passes exactly this local, legally, because that readout sits
under the same `_fov_on` gate and because the margin is defined on the CLAMPED window the kernel
owns. Same class as gate 1's clamp-ownership catch: in a project whose product IS the commentary, a
rule that outgrew its scope is a defect.

### ⚠⚠ FIVE ASSERTS FAILED, AND THEY WERE RIGHT TO — "HELD" IS NOT BIT-IDENTITY

The first draft inherited slice 32's `cureA.miss === ref.miss` and claimed a window that fits the
excursion flies the free arm **bit-for-bit**. **It does not, and the reason is the very thing the
`r > 200` gate exists to exclude.** Measured: EVERY held arm leaves the window in the last metres —
first out at **r = 0.18 / 1.0 / 1.98 / 2.81 / 8.55 m**, at look angles of 21–162° — because the LOS
unit vector swings through a huge angle as `r → 0`. Those few coasting ticks perturb the CPA by
**5e−13 … 1.4e−7 m**. Slice 32's `===` passed only because its 30° window happened not to be
crossed before ITS CPA: **luck of a wider window, not a law.**

⇒ **THE EXACT CLAIM MOVED ONTO THE GATED QUANTITIES.** A `held(win, free)` helper says it in one
place, and every "this window flies the engagement" tooth in the slice now goes through it:

| what | how asserted |
|---|---|
| not one out-of-window tick on the APPROACH | `win.out == 0.0` (bit-exact, `r > 200`) |
| it flew the free arm's own excursion | `win.look_max === free.look_max` (bit-exact) |
| any drop-out is ENDGAME ONLY | `isnan(win.r_firstout) \|\| win.r_firstout < 200` |
| the miss | `abs(win.miss − free.miss) < 1e−6` — a NAMED tolerance with a measured reason |

`r_firstout` is deliberately **UNGATED** — it is the gate's own audit.

### ⚠⚠ AND A COLUMN THAT WOULD HAVE COUNTED NOTHING — THE GATE-1 CATCH, ONE GATE ON

A badly broken arm's CPA is **3697 m**, so it **NEVER ENTERS** the arc's `r ∈ [500, 3000]` m band:
`n_band = 0`. A `sum/max(n,1)` — the harness idiom this arc has used since slice 26 — would have
printed a beautifully quiet **`rms r = 0.00000`, computed from ZERO SAMPLES**, on the arm that
misses by 3.7 km. That is the gate-1 post-review's own finding ("a column that reproduces because
it counts nothing is not a reproduction") arriving in a new quantity, and it is the sharpest form
of seam discipline 3: on a badly broken arm the band metric is not merely misleading, **it is
undefined**. `arm` now returns `n_band` and yields `NaN` for `rms_r`/`sat_band` when it is zero;
**every test that quotes a band number asserts `n_band > 0` first**, and the zero-sample arm is
itself asserted (`win_03.n_band == 0`, both metrics `NaN`).

### The wired ladder (glass R₀ = −0.03, A = −0.15, vy = 200, seed 32)

| `R̂` | FREE rms r | FREE excursion | FREE miss | WINDOWED fov 21 | out % | `t_break` |
|---|---|---|---|---|---|---|
| −0.33 (slice 30's rule) | 0.05879 | 18.138° | 0.184 m | **held** | 0.000 | — |
| −0.24 (the onset) | 0.70983 | 20.623° | 1.450 m | **held** | 0.000 | — |
| −0.18 | 0.93194 | 22.124° | 0.920 m | **2191.99 m** | 42.339 | 5.029 |
| −0.03 (boresight) | 1.07211 | 25.011° | 2.070 m | **3696.89 m** | 72.379 | 1.935 |
| no glass | 0.01589 | 18.132° | 0.191 m | held | 0.000 | — |

⭐ Every FREE arm HITS (< 3.6 m) with the loudest ringing 67× the radome-free reference — the
standing fact of 26–31 — and the SAME design through a 21° window misses by **2383×** more.

### The three claims, each in its own currency

* **THE PREDICATE — `held ⟺ fov > excursion`, as a BRACKETING PAIR, never `ceil`** (seam item 2).
  At `R̂ = −0.18` and `−0.03`: `exc − 0.1°` BREAKS, `exc + 0.1°` HOLDS and flies the free arm's own
  excursion bit-for-bit. ⚠⚠ **Both rows sit clear of slice 32's P5 launch cliff (~18.12°), and that
  is ASSERTED (`exc − 0.1 > 18.2`), not commented** (advisor) — a bracket straddling the quiet arm's
  18.14° would straddle the LAUNCHER, i.e. slice 32's own confound shipped as slice 33's headline.
* ⭐ **TWO THRESHOLDS, NOT ONE — and they are ~0.1° apart** (advisor). `held` and `hits` are
  DIFFERENT predicates. At `R̂ = −0.03` (excursion 25.011°): a window **0.011° short** is out for
  0.104 % and **still HITS at 2.002 m**, within 0.07 m of the free arm; **0.1° short** is out 46.8 %
  and misses by 1.37 km. And `t_break` is the discriminator — the survivable arm loses lock at
  **t = 10.36 s (near CPA)**, the lost one at **4.79 s, while the lead is still building**. Slice
  32's sentence reached by moving the WINDOW instead of the crossing speed. ⚠ Pinned against the
  MEASURED excursion, never a literal 25.0 — the margin is below any measuring grid.
  ⚠⚠ **AND THIS CORRECTS §0's "ABOUT 0.4° WIDE" — GATE 3 MUST NOT INHERIT IT** (advisor). That
  figure came from conflating P4's TWO `R̂` rows (`−0.18`'s 0.374° and `−0.03`'s 0.011° read as one
  band). Measured on the 0.011° grid at `R̂ = −0.03` the survivable band is **~0.05–0.1° wide**:
  0.011° short still hits at 2.002 m, 0.05° short misses by 20.5 m, 0.1° short by 1.37 km. The
  verifier's prose takes the §2 number.
* ⭐⭐ **THE PAYLOAD, as an EXCURSION comparison** (advisor — seam item 2 forbids the `ceil`
  currency, so compare like with like). At `R̂ = radome_slope_worst`, **read off slice 30's SHIPPED
  telemetry** (it is `−0.32999999999999996`, not `−0.33` — exactly the literal this project refuses
  to hardcode): excursion **18.136 / 18.138 / 18.140°** at A = −0.10 / −0.15 / −0.20 against the
  radome-free **18.132°**. The glass gets 2× worse and the requirement does not move; a 19° window
  flies all three. The boresight compensator on the same glass demands 6.9° more.

### Causation and isolation

**CAUSATION** — at FIXED `R̂ = −0.18` and FIXED glass, `α_max` (slice 26's own amplitude instrument,
a causation probe and never a slider) walks the ring and the budget together: rms r
0.673 / 0.932 / 1.169 → excursion 20.669 / 22.124 / 23.696°, and **the same 21° window flies the
quietest and breaks the other two**. ⇒ the ring's AMPLITUDE is the budget item; `R̂` only sets it.

**ISOLATION** (seam items 1 and 3, asserted rather than commented):

* `rms r` on the windowed arm **FALLS** 0.932 → 0.197 (4.7×) while the miss **OPENS** 2383× —
  slice 32's metric inversion, measured. A low `rms r` on a windowed arm cannot tell "stable" from
  "lost lock and stopped driving the loop".
* the windowed arm's own `look_max` is **90.6°** — the post-lock-loss runaway — against the ring's
  actual 22.1°. ⇒ **the predictor and the predicted never come from the same run.**
* ⚠⚠ **DO NOT IMPORT SLICE 32's ISOLATION — IT INVERTS HERE.** Slice 32 could write "`aero_sat` is
  0.00 % in EVERY arm ⇒ a POINTING miss" because its wire had NO GLASS. On this wire the FREE
  ringing arm saturates **48.5 %** of its band and **HITS at 0.92 m** (slice 26's ceiling BOUNDING
  the cycle), while the broken arm saturates **0.00 %** and misses by 2.2 km. Saturation does not
  discriminate in either direction here; the WINDOW does.

### The margin on the wire

`flip == cross == tick 1935` — the tick `seeker_valid` goes 1→0 is the tick the shipped margin
crosses zero. ⭐ **That is the tooth that is NOT a tautology**: `margin ≥ 0 ⟺ seeker_in_fov` is
`x == x` at the KERNEL (gate 1 refused to ship it for that reason), but on the WIRE it is a claim
about the SEAM — that the readout passes the PREDICATE'S OWN inputs (the truth LOS, the clamped
radian window) and not an estimate, the authored degrees, or a stale comp key. At a positive
window `margin == seeker_fov_deg − look_angle` to < 1e−12; at `fov = −5` they **diverge by exactly
5.0** (gate 1's clamp-ownership catch, now measured on the wire, and the reason convention 13
requires the key rather than letting the client subtract). `marg_min < −50°` exercises the
`_finite_coord` side. Cross-toggle off `:six_dof` removes the key while `:att_q` survives.

### The loader — thin, with one genuinely new fact

Slice 33 adds no key, no knob and no rung, so there is nothing to presence-gate and nothing to
refuse. **THE ONE NEW LOADER FACT is that the COMPOSITION goes through**: no scenario has ever
authored glass and a window in one YAML, and every gate-0 probe and both gate-1 wire checks
injected the keys PROGRAMMATICALLY. Asserted through `load_scenario`. ⚠ **No fresh draw-count
testset, deliberately** — no new branch and no new `randn`, and slice 32's corollary already flew
radome × FOV arms under its asserted 2-draw lockstep.

⚠⚠ **AND A GATE-3 ITEM FOUND AT GATE 2 (advisor): SLICE 33's WIRE IS THE FIRST TO CARRY BOTH
MARKER SETS.** `_airframe_view_info` on a composition scenario returns `radome_view` **AND**
`seeker_fov_view` (plus `airframe_6dof`) — where slice 32's own gate-3 testset asserts
`!haskey(info, :radome_view)` on ITS wire **as a feature**. The BUTTON outcome is safe either way
(32 wrote that both DROP it), but **which HUD BRANCH the client selects is undecided and is gate
3's**. Pinned as a test here so gate 3 discovers nothing.

### Byte-identity — PROVEN ON THE WIRE, not by reading the diff

`slice32_verify.gd` re-run against a live server reproduces `docs/STATUS.md` to the digit:
`S32V OK`, exit 0 — miss 1504.679 / 0.480 / 1.126, out 67.982 %, `look_max` 99.47 / 29.01 / 23.86,
lead 32.69 vs 28.89 (the broken arm's inflated lead), `max|y|` 8125.0, the six envelope cells, and
**replay posdiff 0.0**. ⚠ The remaining 26–31 verifiers belong at gate 3 alongside the shipped wire
(advisor): gate 1 redefined `seeker_in_fov`, and slice 32 is its heaviest consumer, so that one
verifier is where a regression would actually surface.

Full suite green, **6062 → 6169** (+107).

**Carried into gate 3:** the shipped `scenarios/slice33_*.yaml` (the ladder at fov 21, both cures
one slider each); the HUD-branch decision above; `net/slice33_verify.gd` + `net/slice33_ui_test.gd`
+ smoke-load + a windowed shot (⚠ `STEPS` a multiple of `emit_every`; ⚠ the verdict helper must be
pure so the UI test can call it; ⚠ size `STEPS` off the SLOWEST arm and assert every arm reached
CPA — ToF varies); the 26–31 verifier re-runs; and the STATUS entry, which **must state the
clamp-ownership relocation** (§1's carry-forward).

---

## §3 — Gate 3 (COMPLETE, 2026-07-29 — 6169 → 6215)

`scenarios/slice33_budget.yaml` (seed 32, `STEPS = 12800 = 16 × 800`, sized off the slowest arm's
11.25 s, every arm asserting it REACHED CPA) — **the FIRST scenario in the project to author GLASS
AND A WINDOW in one file**, and it reproduces gate 2's programmatic world cell for cell. The
as-built detail lives in `docs/STATUS.md`; what belongs HERE is the three things gate 3 discovered
that the plan above did not predict.

### ⚠⚠ THE EMIT GRID UNDER-READS THE EXCURSION BY MORE THAN THE SURVIVABLE BAND IS WIDE

The plan carried the sub-degree cell into the verifier's test set as a requirement (§ the wire:
"the sub-degree cell **R̂ = −0.03, fov = 25.00 against a measured excursion of 25.011°** joins the
test set"). **It cannot, and the reason is a measurement.** A verifier reads FRAMES (every 16th
tick), so the peak look angle it sees is the largest SAMPLED one: **24.9946° against the 25.0108°
the core flies — a 0.016° deficit**, where §2 measured the survivable band at ~0.011–0.05°. Pinning
the cell against the verifier's OWN frame excursion therefore lands ~0.027° under the true one —
the tens-of-metres regime (**20.6 m**), not the **2.002 m** cell `test_missile.jl` measures per
tick. ⇒ the sub-degree claim stays per-tick in the suite; the verifier makes the claim its own
resolution supports, which is still the whole of TWO THRESHOLDS because `t_break` separates them
cleanly (**r = 707 m near CPA** vs **r = 3543 m with the lead still building**). This is
[[ewsim-missile-verifier-sampling]] in a NEW quantity — not the miss but the EXCURSION — and the
general form is: **a bracket is only assertable at a frame verifier if it is wider than the emit
grid's own deficit in the bracketed quantity.**

### ⭐⭐ THE CLIENT NEEDED A BRANCH, AND THE DEFECT IT PREVENTS IS ASSERTABLE AS A NUMBER

§2 flagged the HUD-branch decision as gate 3's and said the button outcome was safe either way.
Both halves held, and the second is sharper than expected. **The button needs NO EDIT AT EITHER
SITE** — both marker branches already hide it and build the same scene, the OPPOSITE of slice 26's
"the drop needs BOTH sites", and that is now asserted rather than assumed. **The HUD is not safe**:
without a composition branch `_seeker_fov_view` wins and slice 32's `_fov_verdict_label` compares
the **LEAD** against the **WINDOW** — and on this wire the lead is ~18.1° inside a 21° window, so it
prints *"IN THE WINDOW — FOV holds the lead"* on the arm that misses by 3.7 km, then *"TRACK BROKEN
— lead outgrew FOV"*. **THE LEAD NEVER OUTGREW THE WINDOW; THE RING DID.** The UI test calls BOTH
helpers with the SAME numbers and asserts they DISAGREE, so the branch is proven necessary rather
than argued for; 32's helper is left VERBATIM and asserted still correct on 32's glass-free wire.
⭐ And the advisor's blocking concern — that a composition is where a chained dispatch silently
freezes one instrument — is discharged by assert: `_radome_qpeak` and `_fov_lost` are two
INDEPENDENT `if` blocks, and both are driven live on ONE wire (the peak-hold on the YAW channel,
1.31 against pitch's 0.10).

### ⚠ THE SHOT'S AIMING DEFECT IS THIS SLICE'S OWN METRIC INVERSION

A 4300 m gate cleared the broken arm's 3696.9 m CPA (slice 32's lesson, inherited) and **still
captured the wrong thing**: 1.8 s after the break the look angle reads **56°** — the post-lock-loss
RUNAWAY, not the ring — and the yaw rate has decayed to 0.205 rad/s, because the parasitic feed is
CUT once the seeker stops measuring. Re-aimed at **5000 m**, just past the break, the pair shows the
MECHANISM: `look 30.1° vs FOV 21.0° / BUDGET LEFT −9.1°` beside a `lead_angle_deg` of **15.32°** —
the engagement's own demand, comfortably inside the window, i.e. exactly the number proving slice
32's verdict would have reported health. **AIM AT THE MECHANISM, NOT ITS AFTERMATH.** Three shots,
one per verdict state; the third (the FREE arm) is the only one that can fire the `← RINGING` tag,
for the same inversion reason.

⚠ **One plan claim was CORRECTED at gate 3.** The scenario's first draft said a 26° ceiling "would
NOT do" because it sits inside the survivable band. **Measured, that is false**: 26 is 0.99° ABOVE
the loudest excursion and reads 0.000 % out. The ceiling is 40 for a different and real reason —
**26 is CURE A's own value, and a free-read endpoint that coincides with a shipped cure would make
one number do two jobs** (the reading that DEFINES the requirement and the one that SATISFIES it).

---

## What ships

### The core

⭐ **ONE new number: `<sid>.seeker_fov_margin_deg` = `fov − boresight_angle`, SIGNED.** The precedent
is slice 18's `terrain_clearance_m` exactly: a signed margin whose **SIGN IS THE VERDICT**
(`margin ≥ 0 ⟺ seeker_valid`), shipped so the client never re-derives the test (convention 13 — the
client NEVER re-tests occlusion). It gives the HUD a needle that the ring visibly eats.

⚠ **NO running-peak key** (advisor): peak-hold is DISPLAY STATE, and slice 27 already settled that
a peak-hold is an instrument, not physics.

⚠ **No new rung, no new knob, no new instability, no new cap.** Both sliders already ship
(`radome_slope_est` from 27/28, `seeker_fov_deg` from 32); the physics of both halves already
ships. What is new is the COMPOSITION, the number that measures it, and the design rule it yields.
Slice 30's shape precisely — its only new core quantity was `radome_slope_worst`, and its payload
was a ring count over a swept engagement.

### The seam — three disciplines that must be WRITTEN, not discovered at gate 3

1. ⚠⚠ **THE PREDICTOR AND THE PREDICTED MUST NOT COME FROM THE SAME RUN.** The excursion that
   predicts a window is measured on an arm with **no window**. The windowed arm's own `look_max` is
   **~90° in every broken cell** — that is the post-lock-loss runaway (slice 32's signature), not a
   read of the ring. This is slice 32's `look_angle`-gating catch and slice 29's stale-readout class
   in a NEW quantity, and it belongs at the kernel and in the test, not only in a probe comment.
2. ⚠ **ASSERT THE INEQUALITY, NEVER `ceil`** (advisor). `critical == ⌈excursion⌉` 16/16 is an
   artifact of the 1° measuring grid; the physical claim is `held ⟺ fov > excursion`. The tooth is
   built backwards from the measurement as a BRACKETING PAIR — a window just below the excursion
   breaks, one just above holds — exactly as slice 32 built its `≤` boundary tooth with `prevfloat`.
   Writing the `ceil` identity would pin a test to the grid it was never about.
3. ⚠ **`rms r` is never read off a windowed arm** (§0's isolation).

### Convention 9 — why the two-mechanism wire is now permitted

Slice 32 kept this composition OFF its showcase because two mechanisms in one view is a confound.
**Here the composition IS the lesson**, which is the legitimate exemption — but it obliges the wire
to carry no THIRD thing:

- `af_alpha_max` is **HELD** on the shipped wire and stays a gate-0 causation probe (§P3a).
- The two live sliders are the two halves of ONE quantity, and convention 9 is satisfied **by
  MEASUREMENT, not by counting sliders** — the slice-27 precedent: the DIAGONAL is `fov` TRACKING
  the excursion, and moving both together leaves `held` UNCHANGED (P2's critical-fov column read as
  a path), so the pair is one axis, not two lessons.
  ⚠ **State the diagonal as tracking, NEVER as `fov = ⌈excursion(R̂)⌉`** (advisor) — seam item 2
  forbids asserting the `ceil` identity, and letting the `ceil` form carry the convention-9 argument
  puts the two statements in tension in one document and invites gate 3 to reach for exactly the
  identity it was told not to pin.

### The wire (proposed — gate 1 confirms)

Slice 32's geometry and glass: seed 32, vy = 200, R₀ = −0.03, A = −0.15, `fov` held while `R̂`
slides. Ladder at fov = 21°: HELD at R̂ = −0.33 (18.14°) and −0.24 (20.62°), LOST at −0.18 (22.12°),
−0.09, −0.03. Both cures are one slider each: **widen the window** (fov → 26 holds everything) or
**aim `R̂` at `radome_slope_worst`** (free, and depth-independent).

⚠⚠ **THE INTEGER LADDER STEPS STRAIGHT OVER THE SURVIVABLE BAND, AND THE TEST SET MUST NOT**
(advisor). Every cell above is either 0.000 % out or kilometres out, while P4's interesting regime
— 0.10 % out, still HITS, `t_break` ≈ 10.3 s — lives within ~0.4° of the excursion. **Slice 32 put
BOTH DIRECTIONS IN THE SAME TEST for exactly this reason**: the survivable arm is what proves the
coasting branch RE-ACQUIRES CLEANLY, and without it that branch is live-looking with no tooth (its
"⭐ AND THIS IS THE PROOF THE COASTING BRANCH RE-ACQUIRES CLEANLY"). ⇒ the sub-degree cell
**R̂ = −0.03, fov = 25.00 against a measured excursion of 25.011°** joins the test set.
⚠ **PIN IT AGAINST THE MEASURED EXCURSION, NEVER A HARDCODED 25.0** — the margin there is 0.011°,
below the measuring grid, so a literal becomes a magic number the next retune silently breaks
(the slice-21 magic-multiple tooth, now pinned against a measured quantity).

### The four proofs (convention 14)

`net/slice33_verify.gd`, `net/slice33_ui_test.gd`, a `Sandbox.tscn` headless smoke-load, a windowed
shot. ⚠⚠ **`STEPS` MUST BE A MULTIPLE OF `emit_every`** (slice 31 lost an hour to the silent hang;
slice 32 used 16000 = 16 × 1000). ⚠ Anything the verdict computes inside `_draw` has no headless
proof — the margin verdict goes in a pure helper the UI test calls. ⚠ ToF varies arm to arm; size
`STEPS` off the SLOWEST arm and assert every arm REACHED CPA. ⚠ Re-run the 26–32 verifiers ON THE
WIRE as the byte-identity check.

---

## Deferred (NAMED)

* ⭐ **A REAL GIMBAL — and it now has its lesson, banked at gate 0.** A head with its own state,
  servo bandwidth, rate limit and mechanical stop. **The lesson it should carry: the gimbal that
  saves your envelope PARKS YOU ON THE WORST GLASS.** A strapdown seeker's body chases the LOS, so
  the look angle stays near the lead; a gimbal deliberately holds the head at the FULL lead angle,
  which is exactly the steep part of the curve slice 28 showed closes the loop. So a gimbal buys the
  envelope back and hands the radome a worse operating point — the same trade in a new place. ⚠ It
  REWRITES 26–31's `look_az` (the bend would key off head-vs-body), which is the byte-identity
  surface of six slices, so it needs a presence-gated head state with the strapdown else-arm
  VERBATIM.
* **A RECTANGULAR / PER-AXIS FOV** — slice 32 ships ONE circular window; a two-axis gimbal really
  does have independent mechanical stops.
* **SEEKER RANGE / SNR ACQUISITION LIMITS** — the other half of "can the seeker see it".
* **THE HANDOVER BASKET as an authored quantity** — slice 32's P5 found the launch look angle is a
  live physical constraint its wire holds fixed.
* Everything 26–32 named and did not spend: estimating `R̂` in flight (blocked by 26's P7A, sharpened
  by 29); a 2-D slope `R(look_az, look_el)`; an asymmetric error curve; a SINGLE IMU; gyro NOISE
  (draw-topology, convention 3); per-axis scale factors and misalignment; the out-of-plane
  MANEUVERING target.
