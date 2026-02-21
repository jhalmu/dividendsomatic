# Database Analysis

> Snapshot taken 2026-02-21. Numbers reflect live PostgreSQL state.

## Overview

23 tables total: **17 active**, **6 legacy**. ~95,700 rows. Data spans 2021-2026.

The schema evolved through three phases:
1. **Initial** (Jan 2026) — flat tables per CSV section (holdings, dividends, broker_transactions)
2. **Unified** (Feb 14) — normalized portfolio_snapshots + positions, old tables renamed `legacy_*`
3. **Instrument-centric** (Feb 19) — master `instruments` table with FK-linked trades, dividend_payments, cash_flows, corporate_actions

---

## Active Tables (17)

### Portfolio Context

#### `instruments` — 349 rows
Master registry. ISIN is the primary identifier (not symbol — symbols get reused, e.g. TELIA).

| Field | Type | Notes |
|-------|------|-------|
| `isin` | string | **required, unique** |
| `cusip`, `conid`, `figi` | string/int | Alternate identifiers |
| `name`, `asset_category`, `listing_exchange` | string | Descriptive |
| `currency` | string | 13 rows still NULL |
| `multiplier` | decimal | Default 1 |
| `type` | string | stock, etf, etc. |
| `sector`, `industry`, `country` | string | Only 39/349 populated |
| `logo_url`, `web_url` | string | From Finnhub/Yahoo |
| `dividend_rate`, `dividend_yield` | decimal | Yahoo Finance declared rate |
| `dividend_frequency` | string | annual/semi-annual/quarterly/monthly |
| `ex_dividend_date` | date | Most recent ex-date |
| `payout_ratio` | decimal | From Yahoo |
| `dividend_source`, `dividend_updated_at` | string/datetime | Provenance tracking |
| `metadata` | map | Extensible JSON blob |

**Relationships:** has_many `instrument_aliases`, `trades`, `dividend_payments`, `corporate_actions`

#### `instrument_aliases` — 407 rows
Maps symbols to instruments with time validity. A single instrument can have multiple symbols (different exchanges, name changes).

| Field | Type | Notes |
|-------|------|-------|
| `instrument_id` | FK | **required** |
| `symbol` | string | **required** |
| `exchange` | string | |
| `valid_from`, `valid_to` | date | Time-bounded validity |
| `source` | string | Import origin |

Unique constraint: `[instrument_id, symbol, exchange]`

#### `trades` — 7,663 rows
IBKR trade executions.

| Field | Type | Notes |
|-------|------|-------|
| `external_id` | string | **required, unique** — IBKR TradeID |
| `instrument_id` | FK | **required** |
| `trade_date` | date | **required** |
| `quantity` | decimal | **required** — positive=buy, negative=sell |
| `price`, `amount` | decimal | **required** |
| `currency` | string | **required** |
| `commission` | decimal | Default 0 |
| `fx_rate` | decimal | To EUR |
| `settlement_date` | date | T+2 typically |
| `raw_data` | map | Original CSV row |

#### `dividend_payments` — 2,138 rows
IBKR dividend records linked to instruments.

| Field | Type | Notes |
|-------|------|-------|
| `external_id` | string | **required, unique** |
| `instrument_id` | FK | **required** |
| `pay_date` | date | **required** |
| `gross_amount`, `net_amount` | decimal | **required** |
| `withholding_tax` | decimal | Default 0 |
| `currency` | string | **required** |
| `fx_rate` | decimal | 746 rows NULL |
| `amount_eur` | decimal | 747 rows NULL |
| `quantity` | decimal | Shares held at pay date |
| `per_share` | decimal | 307 rows NULL |
| `ex_date` | date | |
| `raw_data` | map | Original CSV row |

#### `cash_flows` — 689 rows
Deposits, withdrawals, interest, fees.

| Field | Type | Notes |
|-------|------|-------|
| `external_id` | string | **required, unique** |
| `flow_type` | enum | deposit, withdrawal, interest, fee, other |
| `date` | date | **required** |
| `amount`, `currency` | decimal/string | **required** |
| `fx_rate`, `amount_eur` | decimal | 12 rows missing EUR amount |

#### `corporate_actions` — 30 rows
Splits, mergers, spin-offs.

| Field | Type | Notes |
|-------|------|-------|
| `external_id` | string | Unique |
| `instrument_id` | FK | Optional |
| `action_type` | string | **required** |
| `date` | date | **required** |
| `quantity`, `amount`, `proceeds` | decimal | |
| `raw_data` | map | |

#### `portfolio_snapshots` — 978 rows
One row per day. Immutable history.

| Field | Type | Notes |
|-------|------|-------|
| `date` | date | **unique** |
| `total_value`, `total_cost` | decimal | |
| `base_currency` | string | Default "EUR" |
| `source` | string | Import origin |
| `data_quality` | enum | actual, reconstructed, estimated |
| `positions_count` | integer | Default 0 |

**Relationship:** has_many `positions`

#### `positions` — 24,807 rows
Individual holdings per snapshot. Largest table.

| Field | Type | Notes |
|-------|------|-------|
| `portfolio_snapshot_id` | FK | **required** |
| `date` | date | **required** |
| `isin` | string | All populated (0 nulls) |
| `symbol` | string | **required** |
| `quantity`, `price`, `value` | decimal | |
| `cost_basis`, `cost_price` | decimal | |
| `currency` | string | Default "EUR" |
| `fx_rate` | decimal | |
| `unrealized_pnl`, `weight` | decimal | |

Unique constraints: `[snapshot_id, isin, date]`, `[snapshot_id, symbol, date]`

#### `sold_positions` — 6,291 rows
Historical sold positions for what-if analysis.

| Field | Type | Notes |
|-------|------|-------|
| `symbol` | string | **required** |
| `isin` | string | **5,039 rows NULL (80%)** |
| `quantity`, `purchase_price`, `sale_price` | decimal | **required** |
| `purchase_date`, `sale_date` | date | **required** |
| `realized_pnl` | decimal | Auto-computed |
| `realized_pnl_eur` | decimal | All populated |
| `currency` | string | Default "EUR" |
| `identifier_key` | string | Auto-computed from ISIN or symbol |

No FK to instruments — soft-linked via `isin`/`identifier_key`.

#### `fx_rates` — 607 rows
Currency conversion lookup. 9 currencies (USD, CAD, NOK, JPY, SEK, HKD, GBP, TRY, CHF) against EUR base.

| Field | Type | Notes |
|-------|------|-------|
| `date` | date | |
| `currency` | string | |
| `rate` | decimal | To EUR |

Unique constraint: `[date, currency]`

#### `margin_equity_snapshots` — 7 rows
Daily margin/equity breakdown from IBKR NAV section.

| Field | Type | Notes |
|-------|------|-------|
| `date` | date | **unique** |
| `cash_balance`, `margin_loan` | decimal | |
| `net_liquidation_value`, `own_equity` | decimal | |
| `leverage_ratio`, `loan_to_value` | decimal | Auto-computed |

### Stocks Context

#### `historical_prices` — 21,169 rows
OHLCV candle data. Second-largest table.

| Field | Type | Notes |
|-------|------|-------|
| `symbol` | string | **required** |
| `isin` | string | Soft link |
| `date` | date | **required** |
| `open`, `high`, `low`, `close` | decimal | |
| `volume` | integer | |
| `source` | string | Default "finnhub" |

Unique constraint: `[symbol, date]`

#### `stock_quotes` — 6 rows
Cached real-time quotes. Very sparse.

#### `company_profiles` — 44 rows
Company info from Finnhub/Yahoo. Only 44 of ~349 instruments covered.

#### `stock_metrics` — 9 rows
Financial ratios (PE, PB, EPS, ROE, etc.) from Finnhub. Only 9 instruments.

#### `company_notes` — 0 rows
User-editable investment thesis. Schema exists but never used.

### Market Sentiment Context

#### `fear_greed_history` — 1,397 rows
CNN Fear & Greed Index daily values. Standalone, no FKs.

---

## Legacy Tables (6)

All renamed with `legacy_` prefix in migration `20260219200456`. Data already migrated to new schemas.

| Table | Rows | Original Name | Status |
|-------|------|--------------|--------|
| `legacy_broker_transactions` | 7,407 | `broker_transactions` | Nordnet raw transactions. **7 mix tasks still INSERT into it.** |
| `legacy_dividends` | 6,167 | `dividends` | Old dividend table (mixed IBKR/Yahoo sources). Superseded by `dividend_payments`. |
| `legacy_holdings` | 10,088 | `holdings` | Old holding-per-snapshot. Superseded by `positions`. |
| `legacy_costs` | 4,598 | `costs` | Trading costs extracted from broker_transactions. |
| `legacy_portfolio_snapshots` | 781 | `portfolio_snapshots` (old) | Old snapshots with raw_csv_data blob. |
| `legacy_symbol_mappings` | 115 | `symbol_mappings` | ISIN-to-Finnhub symbol resolution. **Still actively used by SymbolMapper.** |

### Import tasks that still reference legacy tables

These mix tasks INSERT into `legacy_broker_transactions`, `legacy_costs`, `legacy_dividends`, or `legacy_holdings`:

- `mix import.lynx_data`
- `mix import.flex_dividends`
- `mix import.yahoo_dividends`
- `mix import.nordnet`
- `mix import.ibkr`
- `mix backfill_isin`
- `mix migrate_to_unified`

Until these tasks are rewritten, the legacy tables cannot be dropped.

---

## Foreign Key Map

```
instruments ─────┬── has_many ──> instrument_aliases
                 ├── has_many ──> trades
                 ├── has_many ──> dividend_payments
                 └── has_many ──> corporate_actions

portfolio_snapshots ── has_many ──> positions

legacy_broker_transactions ── has_one ──> legacy_costs
```

**Soft-linked tables (no FK constraint, matched at query time):**

- `positions.isin` → `instruments.isin`
- `sold_positions.isin` → `instruments.isin`
- `historical_prices.symbol`/`.isin` → instruments (via SymbolMapper)
- `company_profiles.symbol` → `instrument_aliases.symbol`
- `stock_quotes.symbol`, `stock_metrics.symbol` — same pattern

---

## Data Quality Gaps

### Critical

| Issue | Count | Impact |
|-------|-------|--------|
| `dividend_payments` missing `amount_eur` | 747 / 2,138 (35%) | EUR dividend totals are understated |
| `dividend_payments` missing `fx_rate` | 746 / 2,138 (35%) | Cannot convert to EUR |
| `dividend_payments` missing `per_share` | 307 / 2,138 (14%) | Cannot compute yield per instrument |
| `sold_positions` missing `isin` | 5,039 / 6,291 (80%) | Cannot link to instruments for analytics |

### Moderate

| Issue | Count | Impact |
|-------|-------|--------|
| `instruments` missing `currency` | 13 / 349 | FX conversion fails for these |
| `instruments` missing `sector`/`industry` | 310 / 349 | Sector allocation charts incomplete |
| `instruments` missing `dividend_rate` | 340 / 349 | Only 9 have Yahoo Finance rates |
| `cash_flows` missing `amount_eur` | 12 / 689 | Minor gap in cash flow reporting |
| Orphan instruments (no positions/trades) | 10 | Catalog noise |

### Clean

| Metric | Status |
|--------|--------|
| `positions` with ISIN | 100% — all 24,807 rows |
| `sold_positions` with EUR P&L | 100% — all 6,291 rows |
| Trade deduplication | Clean — `external_id` unique constraint |
| Dividend deduplication | Clean — `external_id` unique constraint |

### Validation Summary (from `mix validate.data`)

- 2,138 dividend records checked, 662 issues (350 info, 312 warning)
- 281 apparent duplicates (same-date IBKR payouts — legitimate for partial fills)
- EUR balance check gap: 12.66% (EUR 10,906 of EUR 88,197 total)
- NLV-based honest margin-aware gap: 16.30%

---

## CSV Import Formats

### IBKR Flex Query (6 types)

Detected automatically by `FlexCsvRouter` based on header signatures.

| Type | Header Signature | Produces |
|------|-----------------|----------|
| `:portfolio` | `MarkPrice` + `PositionValue` | `portfolio_snapshots` + `positions` |
| `:dividends` | `GrossRate` + `NetAmount` | `dividend_payments` (via instruments) |
| `:trades` | `TradeID` + `Buy/Sell` | `trades` (via instruments) |
| `:actions` | `ActivityCode` + `TransactionID` | Multiple tables depending on action type |
| `:activity_statement` | Starts with `Statement,` | Multi-section: instruments, trades, dividends, cash_flows, corporate_actions, fx_rates, NAV snapshots |
| `:cash_report` | `ClientAccountID` + `StartingCash` | `margin_equity_snapshots` |

### Import Pipeline

```
CSV file
  → FlexCsvRouter (detect type, strip duplicate headers)
    → FlexImportOrchestrator (route to parser, auto-archive)
      → IbkrActivityParser (two-pass: instruments first, then transactions)
        → Ecto schemas (instruments → trades/dividends/cash_flows/etc.)
```

Import order matters: instruments must exist before trades/dividends can reference them via `instrument_id`.

### Other Sources

| Source | Mix Task | Target Tables |
|--------|---------|---------------|
| Nordnet CSV | `mix import.nordnet` | `legacy_broker_transactions`, `legacy_costs` |
| Lynx 9A PDF | `mix import.lynx_data` | `sold_positions` (7,163 trades → 4,666 sold positions) |
| Yahoo Finance | `mix import.yahoo_dividends` | `legacy_dividends` |

---

## Scattered Information

Data for the same logical entity is split across multiple tables:

### Instrument data (5 tables)
- `instruments` — ISIN, name, currency, exchange, dividend rate
- `instrument_aliases` — symbol mappings over time
- `company_profiles` — sector, industry, market cap (only 44 rows)
- `stock_metrics` — PE, PB, EPS, ROE (only 9 rows)
- `company_notes` — investment thesis (0 rows)

**Problem:** To get full instrument info you need 5 JOINs. Sector/industry on `company_profiles` duplicates fields on `instruments`.

### Dividend data (3 sources)
- `dividend_payments` — 2,138 IBKR-sourced, FK to instruments
- `legacy_dividends` — 6,167 mixed sources (IBKR + Yahoo), no FK
- `instruments.dividend_rate` — declared forward rate from Yahoo

**Problem:** `legacy_dividends` has 3x more records but no FK linkage. Historical dividend analysis requires querying both tables.

### Price data (3 tables)
- `historical_prices` — 21,169 daily OHLCV candles
- `stock_quotes` — 6 real-time cached quotes
- `positions.price` — snapshot-time price embedded in position rows

**Problem:** `historical_prices` keyed by symbol, `positions` by ISIN. Joining requires going through `instrument_aliases`.

---

## Schema Optimization Recommendations

### 1. Backfill dividend payment gaps

747 dividend_payments missing `amount_eur` and 746 missing `fx_rate`. These can be backfilled from `fx_rates` (607 rows covering 9 currencies, 2021-2026). Write a mix task that:
- Looks up `fx_rates` for the payment's `(pay_date, currency)` pair
- Falls back to nearest available date if exact match missing
- Computes `amount_eur = net_amount * fx_rate`

Estimated fix: ~700 of 747 rows recoverable.

### 2. Backfill sold_positions ISIN

5,039 sold_positions lack ISIN (80%). These came from Lynx 9A PDF import which only had symbol/description. Many can be resolved by matching `sold_positions.symbol` against `instrument_aliases.symbol`. Write a backfill task.

### 3. Enrich instrument profiles

Only 44/349 instruments have company profiles, 39 have sector/industry, 9 have metrics. Fetch missing data from Yahoo Finance or Finnhub for the ~178 instruments that actually appear in current positions.

### 4. Reclassify `legacy_symbol_mappings`

Despite the `legacy_` prefix, this table is actively used by `SymbolMapper`. Either:
- Rename to `symbol_mappings` (drop the legacy prefix), or
- Migrate its data into `instrument_aliases` and retire the table

### 5. Consolidate company data onto instruments

`company_profiles` (44 rows) has `sector`, `industry`, `country` that overlap with fields on `instruments`. Since `instruments` already has these columns (added in migration `20260220170053`), the profile-fetch pipeline should write directly to `instruments` instead of maintaining a separate table.

### 6. Add FK from sold_positions to instruments

Currently soft-linked via `isin`. Adding a proper `instrument_id` FK would enable JOINs and referential integrity. Requires backfilling ISINs first (recommendation 2).

### 7. Drop legacy tables (deferred)

6 legacy tables hold ~29,000 rows. Cannot drop until 7 import mix tasks are rewritten to use new schemas. Priority order:
1. Rewrite `import.nordnet` → use `trades`/`instruments` directly
2. Rewrite `import.flex_dividends` → use `dividend_payments`
3. Rewrite `import.yahoo_dividends` → use `instruments.dividend_rate`
4. Remove `migrate_to_unified` (one-time task, already ran)
5. Remove `backfill_isin` (one-time task, already ran)
6. Drop tables: `legacy_broker_transactions`, `legacy_dividends`, `legacy_holdings`, `legacy_costs`, `legacy_portfolio_snapshots`
7. Decide fate of `legacy_symbol_mappings` per recommendation 4

### 8. Evaluate `company_notes` table

0 rows, never used. Either implement the investment thesis feature or drop the table to reduce schema noise.

---

## Migration History (30 migrations)

### Phase 1: Initial Schema (Jan 29 - Feb 5)
| Migration | Purpose |
|-----------|---------|
| `20260129_create_portfolio_system` | Initial tables |
| `20260129_add_oban_jobs_table` | Background jobs |
| `20260205_create_dividends` | Original dividends |
| `20260205_create_stock_quotes` | Quote cache |
| `20260205_create_sold_positions` | Sold positions |

### Phase 2: Enrichment (Feb 11-13)
| Migration | Purpose |
|-----------|---------|
| `20260211_add_holding_period_*` | Holding period tracking |
| `20260211_create_fear_greed_history` | Market sentiment |
| `20260211_create_company_notes` | Investment notes |
| `20260212_create_stock_metrics` | Financial ratios |
| `20260212_create_broker_transactions` | Raw transactions |
| `20260212_create_costs` | Trading costs |
| `20260212_create_historical_prices` | Price data |
| `20260212_create_symbol_mappings` | Symbol resolution |
| `20260213_add_realized_pnl_eur` | EUR P&L |

### Phase 3: Unified Schema (Feb 14)
| Migration | Purpose |
|-----------|---------|
| `20260214_unified_portfolio_history` | **Major redesign:** new `portfolio_snapshots` + `positions`, old tables renamed to `legacy_*` |

### Phase 4: Instrument-Centric (Feb 19-21)
| Migration | Purpose |
|-----------|---------|
| `20260219_create_clean_tables` | `instruments`, `instrument_aliases`, `trades`, `dividend_payments`, `cash_flows`, `corporate_actions` |
| `20260219_archive_legacy_tables` | Rename old tables with `legacy_` prefix |
| `20260220_add_corporate_action_fields` | Extended corporate actions |
| `20260220_add_enrichment_fields` | Sector, industry, etc. on instruments |
| `20260220_create_fx_rates` | FX rate lookup table |
| `20260221_add_dividend_fields` | Dividend rate/yield/frequency on instruments |

---

## Historical Problems (from 22 resolved GitHub issues)

### Symbol matching (#4, #18, #22)
Symbols are not stable identifiers. TELIA was reused by different companies. Fix: ISIN-first matching strategy with `instrument_aliases` for time-bounded symbol resolution.

### FX conversion gaps (#4, #22)
Non-EUR dividends and positions lacked EUR conversion. Fix: `fx_rates` table + backfill pipeline. Remaining gap: 747 dividend_payments still unconverted.

### Legacy table migration (#18, #22)
Batch re-import after PostgreSQL migration created the unified schema. Old flat tables renamed but not dropped due to import task dependencies.

### Dividend income underestimation
Analytics showed 2-14x underestimation of actual dividend income. Root causes: missing FX conversion, TTM extrapolation errors, mixed per-share vs total-amount formats. Fix: three-tier dividend source (Yahoo declared rate → TTM with frequency → raw TTM sum).

### Test stability (#5, #8-11)
723 tests, 0 failures at session end. Coverage target was 80%.
