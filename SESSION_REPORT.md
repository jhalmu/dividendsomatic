# Session Report — 2026-02-21 (Legacy Instrument Merge & Cleanup)

## Legacy Instrument Merge

### Context
The Positions view showed dashes for dividend columns (est_monthly, projected_annual, yield_on_cost). Root cause: `mix migrate.legacy_dividends` created 29 fake instruments with ISINs like `LEGACY:CVZ`, `LEGACY:AKTIA` and linked 1,256 dividend_payments to them. The same stocks had proper instruments (from IBKR Activity Statements) with real ISINs but zero dividend_payments.

### Changes Made

#### `mix merge.legacy_instruments` (new task)
- Finds all LEGACY: instruments and matches to proper counterparts via instrument_aliases
- Reassigns dividend_payments, trades, corporate_actions in a transaction
- Deduplicates dividend_payments after merge (same instrument + pay_date, keeps IBKR-sourced)
- Includes `--backfill` flag for per_share backfill
- Dry-run by default, `--commit` to execute
- Result: 24 merged, 5 unmatched (2A41, FROo, BCIC, GLAD.OLD, FOT — sold/delisted)
- 27 duplicate dividend_payments removed

#### Legacy Schema Reference Cleanup
Rewrote 8 files to use new schemas (DividendPayment, Trade, Instrument) instead of legacy schemas (Dividend, BrokerTransaction):

| File | Change |
|------|--------|
| `dividend_validator.ex` | DividendPayment + Instrument join (was Dividend) |
| `dividend_validator_test.exs` | DividendPayment + Instrument fixtures |
| `position_reconstructor.ex` | Trade + Instrument join (was BrokerTransaction) |
| `symbol_mapper.ex` | Trade + Instrument join for distinct_isins |
| `fetch_historical_prices.ex` | Trade + Instrument joins |
| `backfill_fx_rates.ex` | Removed legacy dividend backfill function |
| `check_sqlite.ex` | DividendPayment (was Dividend) |
| `process_data.ex` | DividendPayment + Trade (was Dividend + BrokerTransaction) |

Deleted: `migrate_legacy_dividends.ex`, `compare_legacy.ex` (superseded)

#### Deferred: Drop Legacy Tables
Created migration to drop 6 legacy tables but discovered 7 import tasks still INSERT into them. Deleted migration to avoid breaking tests. Prerequisites documented for future cleanup.

### Validation Results

| Metric | Value |
|--------|-------|
| Tests | 716 pass, 0 failures |
| Dividends checked | 2,138 records |
| Issues | 662 (350 info, 312 warning) |
| Duplicates | 281 (same-date IBKR payouts) |
| Missing FX | 1 (NCZ) |
| Balance check | €10,906 (12.66%) WARNING |
| Dividends total | €88,197 |

### Files Changed
- Created: `lib/mix/tasks/merge_legacy_instruments.ex`
- Modified: `dividend_validator.ex`, `position_reconstructor.ex`, `symbol_mapper.ex`, `fetch_historical_prices.ex`, `backfill_fx_rates.ex`, `check_sqlite.ex`, `process_data.ex`, `validate_data.ex`, `portfolio_validator.ex`, `portfolio_live.html.heex`
- Modified tests: `dividend_validator_test.exs`, `portfolio_validator_test.exs`
- Deleted: `migrate_legacy_dividends.ex`, `compare_legacy.ex`
- 17 files changed, +1,024 / -785 lines
