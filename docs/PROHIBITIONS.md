# PROHIBITIONS — what has already been ruled on, and why

**Read this before proposing a new knob, slider or slice candidate; before writing a gate-0 kill
record; and before quoting a past slice's ⚠ as a rule.** `CLAUDE.md` keeps only the NAMES and the
VERDICT WORDS of everything below — the trip-wire that stops a re-proposal mid-sentence. **The
reasoning, the teeth, the numbers and the slice cites live here**, and the full argument lives one
level further down in `docs/DEFERRALS.md` (the kill list), `docs/LESSONS.md` (method) and
`docs/CONVENTIONS.md` (function names, rungs, numbers).

⚠ **A verdict word is not a summary — it is the ruling.** Read it before acting on the line:

⚠ **Read the VERDICT WORD.** **DEAD** = the component does not exist (a cancellation, an identity, an
artifact, an unread key). **DEAD AS A LESSON / ALIVE AS A MODEL** = the hardware is real and shippable, only
the headline died (the two-test rule above). **BLOCKED** = never killed at all. **✅** = SHIPPED since, and
listed only so it is not re-proposed as open.

⭐⭐⭐ **A RULING IS NOT A VERDICT ON THE SIMULATOR (2026-09-06).** Most of what follows failed the
LESSON test, which asks *"does dialing it move the authored scenario's headline metric?"* — a
**SLIDER**, which is ONE trigger among five (**SLIDER · RIVAL · REGIME · CURVE · NULL**). Each entry
below therefore carries a one-line tag saying what it is still worth to the simulator and by which
trigger. ⇒ **The RULING is binding; the TAG is a pointer.** ⚠⚠ A tag NEVER revives the headline the
ruling killed, and `INSTRUMENT` is not a revival at all — it means the item teaches about the
SIMULATOR, has no authorable key and ships nothing. **The cost, the evidence and what would have to
be built are in `docs/DEFERRALS.md` §"THE BUILD LIST" — go there before proposing any of it.**

⚠⚠ **A line here was ruled on ONCE, on a specific scenario, with specific numbers.** Do not paraphrase
a ⚠ into a decision — open the cited slice in `docs/STATUS.md` (`## Slice N`) first. And check a later
slice before quoting an earlier one: **prohibitions in this file HAVE been retracted, and every
withdrawal is listed in §6 below.** Read §6 before quoting anything above it — a ban that was
measured wrong reads exactly like a ban that was measured right.

---

## 1. Do not rebuild — components and candidates already ruled on

- **A nulling-loop head servo** (39) — **DEAD**: an algebraic IDENTITY with the shipped feed-forward. ⚠ FINITE loop gain is un-killed.
  ⇒ **`INSTRUMENT` ONLY — nothing to author** (two architectures that look different and ARE the same). ⚠ FINITE loop gain is a **RIVAL** candidate and is NOT this identity.
- **Memory track / a coasting head** (37) — **DEAD AS A LESSON, ALIVE AS A MODEL**: the cure is the ESTIMATOR's frozen rate, not the head.
  ⇒ **Still worth building — `REGIME`**: the coast rescued ONE boundary cell of fifteen, which is where it bites.
- **A scalar rate-limited fin in the coupled loop** (20) — **DEAD AS A LESSON**: `δ_max` SHADOWS `δ̇_max` (the rate limit itself is SHIPPED, 15). **A second-order FIN actuator** (41) — same verdict, on REPARAMETERIZATION ⇒ ⭐⭐ **measure the SPECTRUM before proposing a dynamic element** (that loop's fin command is ONE spectral line).
  ⇒ **Still worth building — `REGIME`/SHADOW** (20: two limits, only one binds) and **`NULL`** (41: the retune-equivalence IS the finding). ⚠ 41's broadband scope is UNPROVEN — an un-run, un-confounded probe.
- **A rectangular / per-axis window and stop** (45) — **DEAD AS A LESSON, ALIVE AS A MODEL, both halves** *(the 2026-08-18 ruling, untouched — what died was that day's HEADLINE)*. ⭐⭐⭐ **A TRACKER holds both axes near zero so a window's CORNERS are never visited; a SEARCH drives one axis to the rim BY DESIGN.** ⚠ Never quote the box's rescue without its control.
  ⇒ ⚠⚠ **THE WINDOW HALF IS ✅ SHIPPED (55) — do not re-propose it.** What is still open is the **STOP** half, and it opens with its own **750× NULL**: with the azimuth stop at 30°, the miss is 0.1912 m at every elevation stop from 0.04° to 30°, even where the clamp binds 66.66 % of in-band ticks. ⚠ A fan-beam wire flies behind a CIRCULAR trunnion deliberately (`scenarios/slice55_fanbeam.yaml`), and `frames.jl` still names the `√2·stop` readout hazard a per-axis clamp would introduce.
  ⚠⚠ **AND THE ENTRY'S OWN PRICE EXPIRED IN THREE PLACES BEFORE 55 RAN** — 45's blocker (the SEARCH) shipped in 48; its *"a cost claim needs a cost model this simulator does not have"* shipped in 46; and *"byte-identical on 8/9 TRACKING rows"* is FALSE at HEAD, surviving only as *box `(a,b)` ≡ disc `√(ab)`*, which is the LINK BUDGET's identity and not the window kernel's. ⚠ `patch45.py` is unusable in BOTH directions (0 anchor matches; its revert would erase 52/53/54).
- **An "acquisition knife-edge"** (42 gate 1) — **DEAD**: the band is ONE `dt` step and HALVES when `dt` does ⇒ **re-fly any narrow threshold at half `dt`, and read a claimed STEP against NULL first.**
  ⇒ **`INSTRUMENT` ONLY — nothing to author.** ⭐⭐⭐ The best available lesson about trusting a simulator's own output.
- **Seeker noise × the BTT roll loop** — **DEAD as a COUPLING claim** (the roll loop low-passes it away); the noise itself is shipped (25). **A cubic radome curve** — **DEAD**: unbounded slope, no domain.
  ⇒ **`NULL`** (the coupling claim, cheap) and **`INSTRUMENT` ONLY** (the cubic: why a bounded slope is a requirement, not a detail).
- **An angle-domain radome corrector** — **DEAD AS THE DEFAULT, ALIVE AS A MODEL**: it sees the look angle only *through* the bend it removes ⇒ **compensate with a signal not corrupted by what you correct.**
  ⇒ **TIER 1 — `RIVAL`, textbook**: an inferior design that fails PHYSICALLY for a stated reason; ships as an alternative rung, never the default. Already written.
- **PRICING A RE-ACQUISITION** (51) — **DEAD AS A LESSON, ALIVE AS A MODEL** (`turn_start_s` SHIPPED): ⭐⭐⭐ **the miss ban is a ban on a REGION, not on a GAUGE** — ⚠ the BOUNDARY past a blind coast is what does not reproduce (halving `dt` FLIPS whether the track returns), NOT everything past it. ⭐⭐⭐ **A lock is given back by the HEAD, not the ECHO.** ⚠ `head_off > fov` is `in_fov`'s DEFINITION — never a gauge.
  ⇒ Already ALIVE AS A MODEL; the un-built part is the **model gap it NAMED** — no re-cue on an echo returning off-boresight.

## 2. Already SHIPPED — do not re-propose as open, do not re-litigate

- **A SEEKER SEARCH PATTERN** (42/43/45) — ✅ **SHIPPED by 48, its WIDTH by 52; never killed.** ⭐⭐ **The cost of acquiring is the OVERLAP DEFICIT `|err| − fov`, not the pointing error.** ⚠ Do NOT re-litigate that a wider window is free (46 killed it) or that the miss is the gauge.
- **Seeker range / SNR limits AS THE UNBLOCKER** (44) — **DEAD as the unblocker**, ✅ SHIPPED by 46. ⭐⭐ **A detection gate can only price a design variable if the ENGAGEMENT launches OUTSIDE the sensor's horizon** (⚠ 50: near its EDGE). ⚠ **32/34's narrow-window failures are THE SERVO's.** ⚠⚠ **DO NOT QUOTE 44 §VII.1's "100.00 % of `a_max`"** — an r → 0 ENDGAME read.
- ✅ **A TAIL LOBE** (49/50's candidate) — SHIPPED by 53, on the STRAIGHT FLY-PAST rather than the ledger's two-observer wire. ⚠ NOT discharged: a NARROW nozzle lobe, or a target ATTITUDE.
- ✅ **A FAN-BEAM (rectangular) DETECTOR WINDOW** (45's window half) — SHIPPED by 55, at HELD APERTURE. ⭐⭐⭐ **A CIRCLE IS A POINT ON THE ASPECT-RATIO AXIS, NOT THE BASELINE THE AXIS IS MEASURED FROM.** `Ω = θ_az·θ_el`, so a window costs what its PRODUCT costs and the disc a box `(a,b)` trades for is the GEOMETRIC MEAN `√(ab)` — ⚠ never the arithmetic mean and never the equal-AREA radius, both of which are geometric analogies with **no consumer** in this simulator. ⚠⚠ Do NOT quote the 1039.88 → 0.09 m rescue as the headline: a rescue reads as *buying coverage* (42/43's ban, upheld by 46) and only the **MIDDLE** — tall never acquires, round acquires only with a search, wide acquires with none — cannot. ⚠ NOT discharged: the aspect-ratio CURVE (its turning point is measured but ONE ARM DEEP), the ELLIPSE, and the STOP half.
- ✅ **THE ASPECT-RATIO AXIS AT HELD APERTURE** (55's candidate) — SHIPPED by **57**, and ⚠⚠ **AS A `REGIME`, NOT THE `CURVE` IT WAS FILED AS — do not re-propose the turning point.** The interior does not resolve: `max|Δpos|` is **exactly 0.0** across a **15.2×** range of aspect ratio, so there is nothing to rank and `docs/LESSONS.md`:880 disqualifies a flat interior as a ranking gauge. ⭐⭐⭐ **What ships is the LAW: `A²/ω ≤ r ≤ ω/E²`, a band, non-empty iff `A·E ≤ ω`** — four walls predicted on two wires, every one inside its flown bracket, and an infeasible wire where eight arms lock at no ratio at all. ⚠⚠ **THE DIRECTION IS PHYSICS, THE WIDTH IS NOT** (53/54's joint-property rule in a third place): `[1.202, 19.668]` is one geometry's and a second wire's band is eleven per cent wide on the same aperture. ⚠ The `set_param` two-key problem shipped with it as a DERIVED PAIR (the authored pair is the BUDGET; the loader rewrites both half-widths), and its ledger licence — *"only if it carries the curve"* — was read for intent rather than letter, stated as a reading in `docs/plans/slice57.md` §III.4. ⚠ NOT discharged: the ELLIPSE, the STOP half, and a slider that moves the BAND rather than within it.
- ✅ **A GIVE-UP RULE AS THE SLIDER** (53's candidate) — SHIPPED by 54. ⚠⚠ Its ledger blocker was **STALE since slice 3** ⇒ **re-read the CONSUMER before pricing a candidate on the ledger's account of what exists.** ⚠ NOT discharged: a SECOND track (association as a contest), or M-of-N initiation.

## 3. Dead knobs that are BUGS, not features

- **Dead knobs that are BUGS, not features** — `speed` (19, FIXED), `k_δ` (15, cancels exactly), `ζ` on the lag rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude (21) was NOT one — it was a MODEL GAP**, `_integrate_6dof!` passing a CONSTANT `rho` while its own comment reserved the seam for ρ(z). ✅ **FIXED 2026-09-06** — see below.
  ⇒ ✅ **21 WAS A BUG TICKET, NOT A TRIGGER — AND IT IS FIXED (2026-09-06).** `_atm_on`'s third conjunct read `=== :pitch_coupled`, written by slice 21 when that was the only plant integrating a real force; slice 23 added `:six_dof` and nobody came back, so for THIRTY SLICES `:atmosphere === :exponential` was inert on the plant the entire 23–54 arc flies. Closed by a two-way disjunction in the predicate, a two-closure split in `_integrate_6dof!` (stage ρ to `total_accel`, `lift_accel_3d` AND the moment), and the 6-DOF readout block's own `p6` — a FIFTH ρ site nobody had counted. ⚠ Shipped physics + tests only, no scenario or view (the slice-51 `turn_start_s` precedent). ⚠ The point-mass / ballistic half stays open and is a REAL deferral (it touches slice 8's `rk4_step` byte-identity surface). ⭐ **The transferable half: a conjunct that names a specific rung is a claim with a shelf life** — see `docs/LESSONS.md`. ⇒ **`INSTRUMENT` ONLY** for `k_δ` (15, an exact cancellation) and `ζ` (40, a term the model lacks); ⚠⚠ `speed` (19, FIXED), 36 and 31 were repaired plumbing BUGS and stay out even of that.

## 4. Disqualified by non-monotonicity — the SLIDER died, the physics did not

⭐⭐⭐ **AND SLICE 55 SHOWS THE THIRD WAY OUT, BESIDE "SHIP THE CURVE" AND "SHIP THE PHYSICS": HOLD THE CONFOUND FIXED.** `slice48_search.yaml` disqualified `gimbal_fov_deg` because it *"moves the window AND the horizon in opposite directions, so the composite is non-monotone."* Both effects flow through ONE quantity — the solid angle `Ω = θ_az·θ_el` — so a comparison that holds `Ω` fixed and varies only the SHAPE has no composite to be non-monotone in. ⚠⚠ **The measured cost of NOT doing this is 27 flown arms that all tied their controls to every printed digit** (`docs/plans/slice55.md` §II.3): a sweep that moves the cost cannot measure the shape.

- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall` (20, 22), the loss COUNT (49), miss-vs-`rcs_fineness` (50), **`bad`-vs-`pfa` (54)**. ⚠ **NOT component kills — that physics is SHIPPED**; only their use as the showcase SLIDER died.
  ⇒ **TIER 2 — `CURVE`, seven ready-made lessons and NO new physics**: a reversal says an OPTIMUM exists and names where. ⭐ Slice 54 already shipped the technique.

⚠⚠⚠ **AND ONE OF THE SEVEN HAS NOW BEEN FLOWN AND IT DIED — THE LOSS COUNT (49), KILLED AT
GATE 0 ON 2026-09-08** (`docs/plans/slice56.md` §6; as-built numbers in `docs/STATUS.md` §"Slice 56").
**Do not re-propose it, and do not price the remaining six from the "ready-made" cell without reading
this.** The count's `CURVE` is REAL — on the shipped `slice49_aspect.yaml` it runs
**6 14 29 54 78 96 83 57 36 26 21** over `rcs_fineness` 1…12, an interior peak **8 arms wide**, it is
**`dt`-invariant** (54/54, 96/96, 57/57 at half the step), and its turning point is **PREDICTED**:
`SNR* = ln(pfa)/ln(0.5) − 1 = 12.7719 dB` written down before the sweep, crossing at `F* = 4.5943`
against an argmax at 4.0.

⛔ **IT DIES ON REPARAMETERIZATION, AND THE MATCHED PAIR IS THE REASON.** A constant `rcs_m2 = 0.1`
— the shape key ABSENT ENTIRELY — produces **112 losses against the shaped peak's 96**, at a median
in-window SNR of **14.881 dB against 14.870**. Matched to a hundredth of a dB, **the featureless
target chatters MORE.** ⇒ **the count is a function of where the median echo sits relative to the
threshold and does not care what put it there.** Slenderness is one road to the threshold and dimness
is another, cheaper one, so the count can never be a lesson about SHAPE. Slice 39's rule applies: a
knob another shipped knob reparameterizes cannot carry the slice.

⇒ **SLICE 49's *"NEVER QUOTE THE COUNT"* IS REINSTATED VERBATIM, with a SECOND and STRONGER reason
than the one it was written with:** not merely non-monotone, but **not specific to the component the
slider names.** ⚠ What is NOT killed: slice 49's DURATION headline is **re-confirmed** on the same run
(the dimmest constant reaches 4.80 s of longest loss where `rcs_fineness` = 12 reaches 46.60 s —
**9.7×**), and `rcs_fineness` passes the MODEL test unchanged.

⭐⭐⭐ **THE TRANSFERABLE PART, AND IT IS A NEW TEST FOR EVERY REMAINING CANDIDATE ON THIS LIST:**
**a gauge must be scored for SPECIFICITY, not only for RESOLUTION.** Four pre-registered probes
established that the curve was REAL and not one of them asked whether it was a curve in the thing the
slider names; one comparison against a deliberately boring control settled it. ⇒ **before proposing
any of the remaining six, drive the gauge's mediating quantity to the same value with the dullest
other knob available and re-measure.** Method detail: `docs/LESSONS.md` §"A GAUGE MUST BE SCORED FOR
SPECIFICITY".

## 5. Harness / probe and HUD / view traps — MOVED OUT, and deliberately

**They are not here.** The complete trap CHECKLIST — `emit_every` hangs, GDScript format
specifiers, asymmetric frame sampling, defaulted zeros, peak-holds that cannot see a fall, HUD
pixel budgets, occupied corners, dead-code dispatch chains, `get_theme_default_font()` — is
`docs/CONVENTIONS.md` **§16**, with the gate-3-specific teeth in **§14** of the same file and the
long-form story per slice in `docs/LESSONS.md`.

⚠ **This is the fold, not an omission.** A trap had THREE homes (here, §14, and LESSONS.md) and now
has TWO, because the split is a real one: **this file rules on CANDIDATES** — things somebody
proposed and something decided against — while **a trap is a method discipline** nobody proposed
and nothing ruled on. Keeping trap names here made the file look like the place to check before
writing a probe, which it never was.

## 6. RETRACTIONS — rulings this file (or its ancestors) carried and later WITHDREW

⚠⚠ **A rulings file that does not list its own withdrawals is a trap**, because the withdrawn text
is exactly the text most likely to be quoted years later by someone who found it and stopped
reading. Every retraction below was measured on a shipped wire, not argued. **Do not quote the old
reason for any of them.**

- **RETRACTED — `gimbal_fov_margin_deg` is disqualified "because the angle margin improves
  monotonically"** (recorded from slice 47 gate-0 P6b, in slice 46's candidate list; withdrawn by
  slice 47). **Measured on the shipped wire it does NOT improve monotonically** — it separates the
  ends of the slider cleanly in both samplings a HUD author would use (9.9932° → −2.9281° at
  handover; 9.5682° → 1.6764° post-lock), and P6b's inversion came off the sweep that entry itself
  flags as confounded. ⭐⭐ **The replacement is stronger than the ban:** at the handover instant
  `margin + cue = fov`, to a tenth of a degree on four arms — the two "rival" gauges are ONE
  measurement counted from opposite ends. ⇒ the margin stays off the HUD for **REDUNDANCY**
  (convention 9), **not for deception.** ⚠⚠ The identity is **SERVO-CONTINGENT, not definitional**:
  it holds only while the head has SETTLED on its cue (240 °/s here; on slice 35's 8 °/s wire the
  two gauges separate). Full record: `docs/DEFERRALS.md` §"A BAN THIS LEDGER HELPED CARRY IS
  RETRACTED".

- **RETRACTED — "no gate-3 proof DRAGS a slider"** (a slice-52 rule; withdrawn by slice 53).
  Slice 53's verifier drags one, and doing so is **MANDATORY** once the latch lives on the WIRE —
  otherwise a client-side disarm leaves a headless proof reading a stale value as a live
  measurement: green, and false. ⚠⚠ Slice 54 adds the harder half — **something must deliberately
  SURVIVE the drag**, or the tooth only proves you can clear state. Teeth: `docs/CONVENTIONS.md`
  §14 and §16(a).

- **RETRACTED — the outright kills recorded by slices 41 and 43–45** (withdrawn 2026-08-18 by the
  two-test rule). Those gate-0 records applied a LESSON test and wrote up the result as if it
  retired the COMPONENT. It does not: **pass model / fail lesson = "DEAD AS A LESSON, ALIVE AS A
  MODEL"**, and the hardware ships as physics + tests + authorable keys. ⚠ What is NOT retracted:
  the bar for NEW proposals, and slice 39's rule that a reparameterization must not ship as an
  ARCHITECTURE. Full record: `docs/DEFERRALS.md` §"THE 2026-08-18 RE-VERDICT".

- **RETRACTED — "a key with no lesson behind it is not worth a commit"** (a ledger note against
  `maneuver.turn_start_s`; withdrawn 2026-08-31 by slice 51, which shipped the key). ⚠⚠ That
  sentence applied the two-test rule **only half way** — the rule's own words are that a
  pass-model / fail-lesson result *"ships as physics + tests + authorable keys"*, and EWSim is a
  battlefield simulator as well as a teaching instrument. ⚠ It shipped as a KEY, not a slice: no
  scenario, view, verifier or slider, and it must not be quoted as slice 52.

- **RETRACTED — "failed the SLIDER test" read as "failed the LESSON test"** (withdrawn 2026-09-06).
  A lesson needs a TRIGGER and a CONTRAST, and a slider is **one trigger of five** (SLIDER · RIVAL ·
  REGIME · CURVE · NULL). Every kill in §1 that turned on "dialing it does not move the headline
  metric" therefore killed a HEADLINE, not the teaching value — which is why each entry there now
  carries a trigger TAG. ⚠⚠ A tag never revives the headline the ruling killed, and `INSTRUMENT` is
  not a revival at all. Cost and evidence: `docs/DEFERRALS.md` §"THE BUILD LIST".


---

## 7. Gauges that are SOMEONE ELSE'S variable wearing your slice's name (slice 57, 2026-09-08)

⚠⚠ **`gimbal_t_acq_s` / `search_t_lock_s` MUST NOT RANK TWO WINDOWS ON A CUED ENGAGEMENT.** Slice 57
pre-registered `search_t_lock_s` as its gauge and gate 0 refused it twice: it reads −1.0 across the
whole intercept (the head is CUED and never enters the search arm — slice 55's own shipped finding),
and the latch that does stamp equals the tick the target crosses `R_acq` to **0.0000 s on every arm of
two wires**. ⇒ **the window decides WHETHER and the link budget decides WHEN**; the instant is the
horizon crossing wearing a seeker's name, and it carries exactly two states across a 15.2× design
range. ⚠ This is a property of an engagement where the target is already inside the window when the
horizon is crossed — **not a general claim about acquisition times**, and not a kill of either key,
both of which remain correct readouts. Record: `docs/plans/slice57.md` §III.1; the method form is
`docs/LESSONS.md` §"A PRE-REGISTERED GAUGE CAN BE REFUSED BY THE WIRE".

⚠⚠ **AND A KILL CRITERION THAT COMPARES AT DIFFERENT COST IS NOT A CONTROL — slice 57's own F3 fired
on exactly that and its WORDING is RETRACTED.** The 6° disc locks at 2.311 s against the held-aperture
band's 4.940 s, and it subtends `Ω` = 36 deg² rather than 100: **it is a bigger antenna.** The
replacement is a bracketed PRICE — the largest disc that still locks subtends `Ω` ∈ [76.56, 81.00)
deg², so a round design must buy **1.23–1.31× the aperture (0.92–1.16 dB)**. ⚠ Two further disc arms
(2°, 4°) are disqualified by §2's existing rule, not by taste: their horizons (15190.8 m, 7595.4 m)
exceed the **6814 m** launch range, so they lock on the first tick with no blind phase at all.
⚠ The retracted sentence *"at held cost the disc is a single point"* is TRUE and **unfalsifiable**;
a single point cannot lose a comparison, and a retraction that leaves one is not finished.

⚠⚠ **A HUD STRING STATED AS FACT IS A CLAIM WITH A SHELF LIFE.** Slice 55's margin line asserted
*"the el axis is idle"* unconditionally — true at 99.7 % idle on its one authored pair, FALSE at 9 %
on slice 57's high wall — and its neighbour quoted two slice-55 constants as fact. Both are now
DERIVED from the wire (`Sandbox.gd`), with the idle threshold at **0.70 of the half-width**, chosen
against four flown ratios. ⇒ **the moment a slider can move what a sentence describes, that sentence
must be computed from the wire or deleted** — convention 13 one level up: the client may not
recompute physics, and it may not REMEMBER it either. ⚠ Note which slice shipped the defect: **55,
whose own UI test existed to prevent it.** ⭐ And a width tooth must be measured at a slider's
EXTREMES — slice 57's caught a real **403 px against a 400 px column**, because no authored pair in
this repo is wider than 12.5° and that slider's ceiling flies 63.2456°.
