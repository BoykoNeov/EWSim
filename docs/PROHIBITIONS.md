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
slice before quoting an earlier one: prohibitions in this file HAVE been retracted (47 on
`gimbal_fov_margin_deg`, 53 on "no gate-3 proof drags a slider"), and the retractions are recorded on
the per-slice lines in `CLAUDE.md`, not here.

---

## 1. Do not rebuild — components and candidates already ruled on

- **A nulling-loop head servo** (39) — **DEAD**: an algebraic IDENTITY with the shipped feed-forward. ⚠ FINITE loop gain is un-killed.
  ⇒ **`INSTRUMENT` ONLY — nothing to author** (two architectures that look different and ARE the same). ⚠ FINITE loop gain is a **RIVAL** candidate and is NOT this identity.
- **Memory track / a coasting head** (37) — **DEAD AS A LESSON, ALIVE AS A MODEL**: the cure is the ESTIMATOR's frozen rate, not the head.
  ⇒ **Still worth building — `REGIME`**: the coast rescued ONE boundary cell of fifteen, which is where it bites.
- **A scalar rate-limited fin in the coupled loop** (20) — **DEAD AS A LESSON**: `δ_max` SHADOWS `δ̇_max` (the rate limit itself is SHIPPED, 15). **A second-order FIN actuator** (41) — same verdict, on REPARAMETERIZATION ⇒ ⭐⭐ **measure the SPECTRUM before proposing a dynamic element** (that loop's fin command is ONE spectral line).
  ⇒ **Still worth building — `REGIME`/SHADOW** (20: two limits, only one binds) and **`NULL`** (41: the retune-equivalence IS the finding). ⚠ 41's broadband scope is UNPROVEN — an un-run, un-confounded probe.
- **A rectangular / per-axis window and stop** (45) — **DEAD AS A LESSON, ALIVE AS A MODEL, both halves.** ⭐⭐⭐ **A TRACKER holds both axes near zero so a window's CORNERS are never visited; a SEARCH drives one axis to the rim BY DESIGN.** ⚠ Never quote the box's rescue without its control.
  ⇒ **TIER 1 — `REGIME`, textbook**: byte-identical while TRACKING, decisive while SEARCHING; the el stop binds 66–68 % of ticks. Probe code exists.
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
- ✅ **A GIVE-UP RULE AS THE SLIDER** (53's candidate) — SHIPPED by 54. ⚠⚠ Its ledger blocker was **STALE since slice 3** ⇒ **re-read the CONSUMER before pricing a candidate on the ledger's account of what exists.** ⚠ NOT discharged: a SECOND track (association as a contest), or M-of-N initiation.

## 3. Dead knobs that are BUGS, not features

- **Dead knobs that are BUGS, not features** — `speed` (19, FIXED), `k_δ` (15, cancels exactly), `ζ` on the lag rung (40), the handover bias key (36), `(R̂,s)` (31). ⚠⚠ **Launch altitude (21) is NOT one — it is a MODEL GAP**: `_integrate_6dof!` passes a CONSTANT `rho` and its own comment reserves the seam for ρ(z).
  ⇒ ⚠⚠ **21 IS A BUG TICKET, NOT A TRIGGER** — VERIFIED open at `core/src/missile.jl:476–477` on 2026-09-06. ⇒ **`INSTRUMENT` ONLY** for `k_δ` (15, an exact cancellation) and `ζ` (40, a term the model lacks); ⚠⚠ `speed` (19, FIXED), 36 and 31 were repaired plumbing BUGS and stay out even of that.

## 4. Disqualified by non-monotonicity — the SLIDER died, the physics did not

- **Disqualified by non-monotonicity** — `k` (28), `ω_n` (40), `σ_seek` (25), miss-vs-`K` / miss-vs-`α_stall` (20, 22), the loss COUNT (49), miss-vs-`rcs_fineness` (50), **`bad`-vs-`pfa` (54)**. ⚠ **NOT component kills — that physics is SHIPPED**; only their use as the showcase SLIDER died.
  ⇒ **TIER 2 — `CURVE`, seven ready-made lessons and NO new physics**: a reversal says an OPTIMUM exists and names where. ⭐ Slice 54 already shipped the technique.

## 5. Harness traps that cost real hours

- **Harness traps that cost real hours** — `STEPS` MUST be a multiple of `emit_every` (else a SILENT hang); `%g`/`%.2e` are not GDScript specifiers and one bad one kills the WHOLE `%`; frame-sampling error is ASYMMETRIC (a miss samples faithfully, a HIT coarsely); an rms measured where a CLAMP binds reads as a KILL; a key that stops EMITTING makes `.get(k, 0.0)` print a DEFAULTED ZERO as a PASSED TEST — ⚠ WHICH default is a claim (49), and ⚠⚠ when the lesson's NULL is that value only PRESENCE separates them (50); ⚠⚠ **a PEAK-HOLD cannot see a knob that FELL** (52) — re-arm on the drag, at the instant the new setting OWNS the quantity; ⚠ a probe's "has this arm drained?" test must be ARM-SPECIFIC (52). ⚠⚠ **53 RETRACTED "no gate-3 proof DRAGS a slider"** — its verifier does, and it is MANDATORY once the latch lives on the WIRE; ⚠⚠ **54 adds the harder half — something must deliberately SURVIVE a drag.**

## 6. HUD / view traps

- **HUD / view traps** — a HUD budget is in PIXELS and belongs to the VIEW (46, 49), and ⚠⚠ **it is not just a WIDTH but a CORNER THAT MAY ALREADY BE OCCUPIED** (54: two right-anchored blocks collide at EVERY window size, and a width tooth passes). ⚠⚠ **A view marker must go in the chain its own wire REACHES** (54's first draft sat first in `_spatial_hud_kind()` and was DEAD CODE on a `:cfar` wire, reading as handled), must separate wires differing only by the SLIDER, and must be gated on the author's KEY, never the slider's VALUE. ⚠ **Gate a windowed shot on the WIRE, never a FRAME COUNT** (54), and ⚠ a CUMULATIVE gauge read mid-pass is not the pass's answer. ⚠ `get_theme_default_font()` does not exist on `Sandbox.gd` — it breaks EVERY dependent script; the file has one `_font`. Teeth: `docs/CONVENTIONS.md` §14.
