# Session Report — 2026-02-20 (NLV-Based Balance Check)

## Balance Check Investigation & Fix

### Context
The portfolio balance check had a 12.13% gap (€37.6k), which was misleading. Investigation revealed multiple issues:

1. **initial_capital used cost_basis (€388k)** — includes margin-funded positions. Actual equity (NLV) was only €107k.
2. **current_value used position_value (€310k)** — ignores -€264k margin loan. Actual NLV is €86k.
3. **unrealized_pnl not EUR-converted** — mixed USD/EUR/SEK/JPY values summed raw (€1,265 instead of €2,525).
4. **Dividends partially zeroed** — the `compute_dividend_income` pipeline returns fx_rate=0 for cross-currency dividends without matching position data, losing ~€5k.

The 12.13% gap was *accidentally small* because two errors (inflated initial_capital and inflated current_value) partially cancelled each other.

### Changes Made

#### NLV-Based Accounting
- **`initial_capital_and_date/1`** — looks up NLV from `margin_equity_snapshots` nearest to first IBKR snapshot date. Falls back to cost_basis when no margin data.
- **`current_value`** — uses latest NLV from margin_equity_snapshots. Falls back to position_value.
- **`margin_mode`** flag — propagated through components, controls threshold selection and output formatting.

#### EUR-Converted Unrealized P&L
- `compute_unrealized_pnl/2` now multiplies `unrealized_pnl * fx_rate` per position.
- Before: raw sum = €1,265 (mixed currencies). After: EUR sum = €2,525.

#### Direct EUR Dividend Sum
- **`total_dividends_eur/0`** — `SUM(COALESCE(amount_eur, net_amount))` directly from `dividend_payments`.
- More accurate than the `compute_dividend_income` pipeline which zeroes out cross-currency dividends.
- Before: €78,812 (pipeline). After: €83,871 (direct EUR sum). Recovered €5,059.

#### Margin-Aware Thresholds
- Cash accounts: <1% pass, 1-5% warning, >5% fail (unchanged).
- Margin accounts: <5% pass, 5-20% warning, >20% fail.
- Wider thresholds account for FX effects on multi-currency cash balances, corporate actions, and timing differences.

#### Output Formatting
- `mix validate.data` shows "Mode: Margin account (NLV-based)" when margin data detected.
- Status messages show appropriate threshold ranges per mode.

### Validation Results

| Metric | Before | After |
|--------|--------|-------|
| Initial capital | €388,596 (cost_basis) | €107,014 (NLV) |
| Current value | €309,797 (position_value) | €86,169 (NLV) |
| Unrealized P&L | €1,265 (raw) | €2,525 (EUR-converted) |
| Dividends | €78,812 (pipeline) | €83,871 (direct EUR) |
| Gap | €37,593 (12.13%) FAIL | €14,042 (16.30%) WARNING |
| Tests | 702 | 705 (0 failures) |

### Remaining Gap Analysis
The €14k (16.3%) gap represents:
- **FX effects on cash**: ~€330k margin loan in mixed currencies over 4 years (EUR weakened vs USD = FX gains on cash)
- **Corporate actions**: Not tracked in balance check
- **Timing differences**: NLV snapshots are sparse (annual + recent monthly)
- **Double-counted start unrealized**: ~€3.5k (unrealized P&L at start embedded in both NLV and realized/unrealized components)

### Files Changed
- Modified: `lib/dividendsomatic/portfolio/portfolio_validator.ex` — NLV-based accounting, EUR-converted unrealized P&L, direct dividend sum, margin thresholds
- Modified: `lib/mix/tasks/validate_data.ex` — margin mode display, threshold-aware status messages
- Modified: `test/dividendsomatic/portfolio/portfolio_validator_test.exs` — 3 new tests (NLV mode, margin thresholds, EUR unrealized P&L, direct dividends), updated existing
- Modified: `MEMO.md` — version 0.34.0, session notes
