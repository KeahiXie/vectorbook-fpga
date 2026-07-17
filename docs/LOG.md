# NanoTrader aka. Vectorbook — Iteration Log
Author: Keahi Xie

Two logs in one file:
- **Concepts** — hardware/design knowledge picked up, organized by topic. The reusable half.
- **Bug history** — what broke, organized by file. Symptom / Cause / Fix / Lesson, kept short.

---

# Concepts learned

One dated block per session. Append at the end of the day; topic labels inline in bold.

### 2026-07-16

**Hardware arithmetic**
- Division is expensive (no dedicated hardware; multi-cycle or huge logic), multiplication is cheap. Hence threshold as num/denom + cross-multiply: `b/a >= n/d` becomes `b*d >= a*n`, zero division.
- Product width: unsigned N-bit × M-bit needs N+M bits. 8×8 → 16, or it silently wraps.
- Unsigned subtraction has no negatives: 16'd100−16'd150 = 65486. Wrapped values sail past ≥ checks — guard with explicit ordering (`ask > bid`) before subtracting.

**RTL structure**
- Branch order IS logic: if/else chains resolve overlaps by position, encoding decisions I never made (tie → BUY). Fix: flat decision table first, transcribe row by row; each else-if checks only what's new.
- Level vs pulse: level = "currently true" (book_valid), pulse = "just happened" (book_update). Default-low-then-set makes a clean one-cycle pulse. Applies to TB driving too.
- Compute a gating condition once, reuse the wire — two hand-written copies diverge eventually.
- Renames across trust boundaries carry meaning: order_quantity (config) → proposal_quantity (requested) → order_quantity (risk-approved).

**Verification**
- `!==`/`===` in checkers, `==`/`!=` in RTL: `!==`/`===` compare in bit-wsie, so X input cannot slide.
- Sampling race: reading a signal at the exact posedge that updates it is a scheduling coin-flip. `@(posedge clk); #1;` reads settled values.
- Count latency off the waveform, not belief. My send task consumes one edge internally. Measured: 2 cycles book_update → order_valid.
- Boundary-value testing: `>=` vs `>` differ at exactly one input; only a vector AT the boundary (T2, spread==min_spread) catches the wrong character. Every "at least/at most" deserves one.
- A PASS only counts if I know why it passed — two bugs canceled into false PASSes; the tell was a wrong *reason code*, not a wrong result.
- Read the reject reason before blaming a module: T2 failed with reason=3 (quantity) — its setup was poisoned, its target logic was fine.

**Market microstructure (minimum viable)**
- Bid = best buyer price, ask = best seller price, spread = ask−bid.
- Order-book imbalance = queue-depth ratio as a direction signal.
- Buy transacts at the ask, sell at the bid.
- Pre-trade risk gates are regulatory (SEC 15c3-5, MiFID II RTS 6) — why risk_mini alone owns the kill switch: one authoritative gate.

### 2026-07-15

**RTL structure**
- Atomic writes: fields describing one logical thing (a quote, a proposal) update together under one gate — per-field conditions allow mixed old/new states that never existed on the wire.







# Bug history

### 2026-07-16 — Part 2 session
**Result:** all 7 vectors pass (V1–V6 + T2). Conventions locked: active-high rst · side 0=buy 1=sell · reason 0=none 1=disabled 2=killed 3=over-max.

## strategy_mini.sv

**Buy/sell checks in wrong branch**
- **Symptom:** proposed when spread failed; silent when it passed.
- **Cause:** imbalance checks nested under the spread-fail else.
- **Fix:** rebuilt from the decision table.
- **Lesson:** see Concepts → branch order IS logic.

**Tie resolved to BUY**
- **Symptom:** none in sim — caught in review.
- **Cause:** if/else priority; my design said no-propose on tie.
- **Fix:** explicit `buy && sell → no propose` branch first.

**Crossed book passed the spread gate**
- **Symptom:** bid=150/ask=100 → spread=65486, gate passes (traced, not simmed).
- **Cause:** unsigned wraparound.
- **Fix:** explicit `ask > bid` guard.

**sell_signal from wrong products**
- **Symptom:** phantom sell at bid=2 ask=1 n=3 d=2.
- **Cause:** mirrored buy's products instead of deriving sell's own pair.
- **Fix:** four independent products.

**REVERTED: `>=` → `>` on both comparators**
- **What/why wrong:** tried to make the tie disappear; killed every exact-threshold proposal (6>=6 must fire) and made the tie branch dead code.
- **Revert:** back to `>=`; tie has its own branch. *(Phase 8 reverted-change entry.)*

## risk_mini.sv

**No proposal_valid gate**
- **Symptom:** none visible — evaluated every cycle, could emit orders from stale wires. Worst-severity bug of the session.
- **Fix:** proposal_valid as outermost gate.

**Accept branch didn't clear rejected_reason (+ fixed comment, not code)**
- **Symptom:** order_valid=1 with reason=KILLED simultaneously possible; first "fix" updated only the comment.
- **Fix:** reason <= 0 in accept branch, verified in the diff this time.
- **Lesson:** doc promising what code doesn't do is worse than no doc.

**kill_swtich typo as a port name**
- **Fix:** renamed before top-level wiring made it load-bearing.

## strategy_risk_mini_tb.sv

**book_valid never driven**
- **Symptom:** would be all-quiet sim; caught in review.
- **Fix:** raise once after reset — it's a level.


**Config poisoning ×5**
- **Symptom:** V5 rejected on kill not quantity; T2 rejected on quantity 150 leaked from V5 — twice, once after being flagged.
- **Fix (tactical):** per-vector restore lines.
- **Fix (structural, for Phase 1):** reset_config() task at the top of every scenario.

**Checker sampled one cycle late**
- **Symptom:** V1/V2 FAIL against a waveform showing their pulses; V4/V5 false-PASSed on stale reason values.
- **Cause:** repeat(2) after a send task that already consumes one edge.
- **Fix:** repeat(1) + #1.

---

###  2026-07-15 Part 1 — one_sysbom_book, mini_market_top

## one_symbol_book.sv

**Per-field writes instead of one atomic write**
- **Symptom:** none in sim at first — design smell caught in review; Scene C/D would expose it.
- **Cause:** each field updated under its own condition, so one cycle could show new bid price next to old ask quantity — a book state no real message ever contained. Downstream computes spread from two prices that never coexisted.
- **Fix:** single `if (write_en)` gating all four field assignments — one condition, one edge, indivisible.
- **Lesson:** fields that describe one thing update as one write. Same rule honored in strategy_mini (all proposal_* fields assigned together per branch).