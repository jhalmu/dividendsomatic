---
name: yield-audit
description: Weekly yield formula audit. Use after dividend formula changes, FX-related imports, or weekly during EOD.
---

# Yield Formula Audit

## When to Run

- Weekly during EOD workflow
- After any dividend formula or FX logic changes
- After FX-related CSV imports
- After Activity Statement imports (new dividend_payments may trigger TTM recomputation)
- When yield values look suspicious (e.g., >40% for blue chips, or exactly 2x expected)

## Checklist

1. **Run tests** — `mix test` must pass (includes yield FX regression tests)
2. **Run validation** — `mix validate.data` — check for missing FX rates (check #7)
3. **Spot-check USD stock** — open app, verify Current Yield for a USD stock (e.g., TRIN) against IBKR
4. **Spot-check EUR stock** — verify Current Yield for an EUR stock (e.g., AKTIA) against IBKR
5. **Cross-currency check** — verify TELIA yield is ~4-5% (NOT ~48% which indicates div_fx=1.0 bug)
6. **Invariant check** — for each symbol: `current_yield ≈ projected_annual / position_value × 100`

## Formula Reference

```
yield = (annual_per_share × div_fx) / (price × pos_fx) × 100

div_fx = div_fx_rate || pos.fx_rate || 1.0
pos_fx = pos.fx_rate || 1.0

projected_annual = annual_per_share × quantity × div_fx
```

### Key Invariant

```
projected_annual / (price × quantity × pos_fx) ≈ current_yield / 100
```

If these diverge, yield and projected_annual are using different FX rates — this is the exact bug pattern from the div_fx_rate=1.0 regression.

## Reference Values (Feb 2026 Baseline)

| Symbol | Currency | Expected Yield | Type |
|--------|----------|---------------|------|
| TELIA | SEK div / EUR pos | ~4.57% | Cross-currency |
| TRIN | USD/USD | ~13.63% | Same-currency |
| AKTIA | EUR/EUR | ~6.59% | Same-currency |
| TCPC | USD/USD | ~21.69% | Same-currency |

These are approximate — actual values shift with market prices. Use as sanity bounds:
- TELIA: 3-6% normal, >10% suspicious
- TRIN: 10-17% normal, >25% suspicious (has quarterly supplementals — base rate only)
- AKTIA: 5-9% normal, >15% suspicious
- TCPC: 18-25% normal, >35% suspicious (BDC with PIL splits)

## Red Flags

| Symptom | Likely Cause |
|---------|-------------|
| USD stock yield ~17% too high | div_fx defaulting to 1.0 instead of pos.fx_rate |
| Cross-currency yield >10× expected | div_fx_rate nil, fallback wrong |
| projected_annual ≠ yield × value | FX mismatch between yield and projection |
| All USD yields inflated equally | Systematic div_fx fallback bug |
| Yield exactly ~2× expected | PIL/withholding split double-counting per_share |
| BDC yield includes supplementals | Stored rate includes quarterly supplemental dividends |

## Known BDC/PIL Patterns

IBKR creates **two dividend_payment records per event** (PIL portion + withholding adjustment), both with the same `per_share`. Without deduplication, TTM sums each record separately, inflating the annual rate ~2×.

**Fix (Feb 2026):** `compute_annual_dividend_per_share` deduplicates by `(ex_date, per_share)` before summing. Same fix applied in `backfill_dividend_rates.ex:compute_rate_from_payments`.

**BDC special dividends:** TRIN pays both base monthly ($0.17) and quarterly supplemental ($0.51). IBKR reference yield uses base rate only ($2.04/yr). Manual override in `backfill_dividend_rates.ex` protects this.

**Manual overrides** (in `@manual_overrides`): TCPC ($1.00 quarterly), TRIN ($2.04 monthly base), TELIA ($2.03 quarterly), Nordea ($0.96 semi-annual). Source "manual" is protected from Yahoo and TTM overwrite.

## Regression Tests

**Yield FX** — `test/dividendsomatic/portfolio_test.exs` under `describe "yield FX consistency"`:

1. **Same-currency (USD/USD)** — nil div_fx_rate must not inflate yield
2. **Cross-currency (SEK/EUR)** — explicit div_fx_rate used correctly
3. **Consistency** — projected_annual and current_yield use same FX logic
4. **PIL dedup** — PIL/withholding splits with same (date, per_share) counted once

**PIL dedup unit tests** — `test/dividendsomatic/portfolio/dividend_analytics_test.exs`:

1. **Dedup same date+per_share** — two records → one per_share counted
2. **Keep different per_share on same date** — regular + special both counted
3. **Unique date counting** — extrapolation uses date count, not record count

## Key Files

- `lib/dividendsomatic/portfolio.ex` — `symbol_current_yield/3`, `symbol_yield_on_cost/3`, `symbol_projected_annual/3`, `compute_best_annual_per_share/5`
- `lib/dividendsomatic/portfolio/dividend_analytics.ex` — `compute_annual_dividend_per_share/2` (with PIL dedup)
- `lib/mix/tasks/backfill_dividend_rates.ex` — `@manual_overrides`, `compute_rate_from_payments/2` (with PIL dedup)
- `test/dividendsomatic/portfolio_test.exs` — yield FX + PIL dedup regression tests
- `test/dividendsomatic/portfolio/dividend_analytics_test.exs` — PIL dedup unit tests
