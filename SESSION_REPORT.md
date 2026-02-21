# Session Report — 2026-02-21 (Database Cleanup & Integrity System)

## Overview

Complete database cleanup: dropped all 6 legacy tables after migrating their data to clean normalized schemas. Built persistent integrity check system with Oban daily worker. Archived CSV/PDF data files.

## Legacy Table Migration & Drop

### Tables Dropped

| Table | Rows | Action |
|-------|------|--------|
| `legacy_holdings` | 10,088 | All in `positions` — **dropped** |
| `legacy_portfolio_snapshots` | 781 | All in `portfolio_snapshots` — **dropped** |
| `legacy_symbol_mappings` | 115 | 34 resolved → `instrument_aliases`, 38 no instrument, 43 unmappable — **dropped** |
| `legacy_dividends` | 6,167 | 15 new broker → `dividend_payments`, 285 dups skipped, 5,835 yfinance → JSON archive — **dropped** |
| `legacy_broker_transactions` | 7,407 | 3,818 trades, 25 dividends, 257 cash flows, 159 interest, 98 corporate actions — **dropped** |
| `legacy_costs` | 4,598 | 158 interest → `cash_flows`, rest already on trades/dividends — **dropped** |

### Migration Tasks Created

| Task | Purpose |
|------|---------|
| `mix migrate.symbol_mappings` | Resolved mappings → instrument_aliases |
| `mix migrate.legacy_dividends` | Broker dividends → dividend_payments, yfinance → JSON |
| `mix migrate.legacy_transactions` | buy/sell → trades, dividends → dividend_payments, etc. |
| `mix migrate.legacy_costs` | Interest/fees → cash_flows |

### Modules Deleted (13)

**Schemas (6):** `holding.ex`, `legacy_portfolio_snapshot.ex`, `dividend.ex`, `broker_transaction.ex`, `cost.ex`, `symbol_mapping.ex`

**Import tasks/processors (7):** `import_ibkr.ex`, `import_nordnet.ex`, `import_flex_dividends.ex`, `import_yahoo_dividends.ex`, `import_lynx_data.ex`, `process_data.ex`, `backfill_isin.ex`, `merge_legacy_instruments.ex`, `migrate_to_unified.ex`, `dividend_processor.ex`, `cost_processor.ex`, `sold_position_processor.ex`

### Modules Rewritten

| Module | Change |
|--------|--------|
| `integrity_checker.ex` | `BrokerTransaction` + `Dividend` → `Trade` + `DividendPayment` + `Instrument` |
| `data_gap_analyzer.ex` | `BrokerTransaction` + `Dividend` → `Trade` + `DividendPayment` |
| `symbol_mapper.ex` | `SymbolMapping` → `InstrumentAlias` |
| `stocks.ex` | `SymbolMapping` → `Instrument` + `InstrumentAlias` |

## Schema Integrity System (NEW)

### `SchemaIntegrity` module — 4 checks

1. **Orphan check** — instruments with no trades/dividend_payments, positions with no snapshot, aliases with no instrument
2. **Null field check** — dividend_payments missing amount_eur/fx_rate/per_share, instruments missing currency, sold_positions missing ISIN
3. **FK integrity check** — trades/dividends/corporate_actions pointing to non-existent instruments
4. **Duplicate check** — duplicate external_ids in trades/dividends/cash_flows, duplicate snapshot dates

### Oban IntegrityCheckWorker

- Runs daily at 06:00 UTC
- Logs results and warns on new issues
- Wired into `config/config.exs` crontab

### Current integrity status

- 11 orphan instruments (info)
- 5,039 sold positions missing ISIN (info)
- 13 instruments missing currency (warning)
- 767 non-EUR dividends missing fx_rate (warning)
- 787 dividends missing amount_eur (info)

## Data Archive

- Archived `csv_data/` + `data_archive/` → `../dividendsomatic_data_2026-02-21.zip` (345MB)
- YFinance dividend history exported to `data_archive/yfinance_dividend_history.json` (5,835 records)

## Test Suite

- **666 tests, 0 failures** (25 excluded Playwright)
- Deleted 5 obsolete test files (broker_transaction, cost, processors, yahoo_dividend_parser, ibkr_flex_dividend_parser, import_nordnet)
- Created 2 new test files (schema_integrity_test, integrity_check_worker_test)
- Fixed tests: schema_test (Dividend removed), stocks_test (SymbolMapping → InstrumentAlias), data_gap_analyzer_test (new schemas)

## Validation Summary

- **Dividend validation**: 2,178 checked, 696 issues (323 warnings, 373 info)
- **Balance check**: 6.77% WARNING (margin account, NLV-based)
- **Schema integrity**: 4 checks, 5 issues (2 warnings, 3 info)

## Migrations

| File | Purpose |
|------|---------|
| `20260221130400_drop_empty_legacy_tables.exs` | Drop legacy_holdings, legacy_portfolio_snapshots |
| `20260221130500_drop_legacy_symbol_mappings.exs` | Drop legacy_symbol_mappings |
| `20260221130600_drop_legacy_dividends.exs` | Drop legacy_dividends |
| `20260221131500_drop_legacy_costs_and_broker_transactions.exs` | Drop legacy_costs + legacy_broker_transactions |
