# Portfolio Balance Check Design

**Date:** 2026-02-20
**Status:** Approved

## Goal

Validate the accounting identity: `current_value ≈ net_invested + total_return`

This catches data import errors, missing cash flows, or FX conversion issues by verifying that all components add up.

## Module: `Dividendsomatic.Portfolio.PortfolioValidator`

Follows `DividendValidator` pattern — structured issue reporting with severity levels.

### Public API

```elixir
PortfolioValidator.validate() :: %{
  checks: [check],
  summary: %{passed: integer, warnings: integer, failed: integer}
}
```

### Balance Check Structure

```elixir
%{
  name: :balance_check,
  status: :pass | :warning | :fail,
  expected: Decimal,         # net_invested + total_return
  actual: Decimal,           # current_value (from latest snapshot positions)
  difference: Decimal,       # absolute delta
  difference_pct: Decimal,   # percentage of current_value
  tolerance_pct: Decimal,    # 1.0
  components: %{
    net_invested: Decimal,
    total_deposits: Decimal,
    total_withdrawals: Decimal,
    realized_pnl: Decimal,
    unrealized_pnl: Decimal,
    total_dividends: Decimal,
    total_costs: Decimal,
    total_return: Decimal,
    current_value: Decimal
  }
}
```

### Status Thresholds

- `:pass` — difference < 1% of current_value
- `:warning` — difference 1-5%
- `:fail` — difference > 5%

## Data Sources

- **current_value**: Sum of `position.value * position.fx_rate` from latest snapshot
- **net_invested**: `total_deposits - total_withdrawals` from cash_flows table
- **realized_pnl**: Sum from sold_positions table
- **unrealized_pnl**: Sum of `position.unrealized_pnl` from latest snapshot positions
- **total_dividends**: Aggregated from dividend_payments table
- **total_costs**: ABS(interest + fees) from cash_flows table
- **total_return**: `realized_pnl + unrealized_pnl + total_dividends - total_costs`

## Integration

Add "Portfolio Balance" section to `mix validate.data` output:

```
═══ Portfolio Balance Check ═══
  Net invested:     €142,350.00
  + Total return:   €23,456.78
    (Realized P&L:   €8,100.50)
    (Unrealized P&L: €12,200.00)
    (Dividends:      €5,156.28)
    (Costs:         -€2,000.00)
  = Expected value: €165,806.78
  Current value:    €165,300.00
  Difference:       €506.78 (0.31%)
  Status:           ✓ PASS (within 1% tolerance)
```

## Testing

- Balance within tolerance → `:pass`
- Balance outside 1% but within 5% → `:warning`
- Balance outside 5% → `:fail`
- Edge case: empty portfolio (no snapshot)
- Edge case: zero current_value
