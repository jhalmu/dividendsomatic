# Session Report — 2026-02-17 (Night)

## Gmail API Integration + Multi-Type Flex Import

### Context
Extended the Gmail module to handle all 4 IBKR Flex CSV report types (not just Activity Flex). Configured OAuth2, fixed date parsing, and resolved integrity checker issues.

### Changes Made

#### Gmail Module Rewrite (`gmail.ex`)
- **New `search_flex_emails/1`** — searches Gmail for all 4 Flex types (Activity, Dividend, Trades, Actions) in one call
- **New `import_all_new/1`** — downloads CSV, auto-detects type via FlexCsvRouter, routes to correct pipeline
- **`route_by_type/4`** — clauses for `:portfolio`, `:dividends`, `:trades`, `:actions`, `:unknown`
- `search_activity_flex_emails/1` kept as backward-compatible wrapper
- Fixed sender: `noreply@` → `donotreply@interactivebrokers.com`
- Fixed date parsing: IBKR uses MM/DD/YYYY (US format), code had DD/MM/YYYY
- Credo fixes: extracted `search_or_empty/3`, replaced `with` single-clause with `case`

#### IntegrityChecker Enhancement
- **New `run_all_from_string/1`** — parses CSV from string (used by Gmail import)
- Extracted shared `run_checks/1` helper to DRY up `run_all/1` and `run_all_from_string/1`

#### OAuth2 Configuration
- Generated new OAuth refresh token via localhost:8085 callback flow
- Published OAuth app from Testing → Production (no more 7-day token expiry)
- `gmail.readonly` scope (restricted) — 100 user lifetime cap, fine for single-user app

#### Test Fixes
- Updated Gmail tests: MM/DD/YYYY format, multi-type search API
- Fixed pre-existing `StockLiveTest` failure: `fetched_at` was hardcoded 7+ days ago, causing staleness check to fail. Now uses `DateTime.utc_now()`.

### Quality
- 547 tests, 0 failures, 0 credo issues
- Gmail API verified: token refresh works, email search returns results, CSV download and snapshot import functional

---

# Session Report — 2026-02-17 (Evening)

## Multi-CSV Import Pipeline + Integrity Checking

### Context
The project previously only imported Portfolio.csv (daily holdings snapshots). IBKR Flex reports deliver 4 CSV types via email. This session implemented a complete multi-CSV import pipeline that auto-detects and routes all 4 types, plus an integrity checker that cross-references Actions.csv against the database.

### Changes Made

#### Step 1: FlexCsvRouter — CSV Type Detection
- **New:** `lib/dividendsomatic/portfolio/flex_csv_router.ex`
- Detects CSV type from headers: `:portfolio`, `:dividends`, `:trades`, `:actions`
- Strips duplicate header rows that IBKR inserts mid-file
- 10 tests

#### Step 2: Dividend CSV Parser (11-column format)
- **New:** `lib/dividendsomatic/portfolio/flex_dividend_csv_parser.ex`
- Parses new 11-column format: Symbol, ISIN, FIGI, AssetClass, Currency, FXRate, ExDate, PayDate, Quantity, GrossRate, NetAmount
- Handles negative NetAmount (withholding tax entries) via abs()
- **Migration:** Added `figi`, `gross_rate`, `net_amount`, `quantity_at_record`, `fx_rate` fields to dividends table
- **Schema:** Updated `dividend.ex` with new fields
- **Mix task:** `mix import.flex_div_csv path/to/Dividends.csv`
- **Context:** `Portfolio.import_flex_dividends_csv/1` with ISIN+ex_date dedup
- 13 tests

#### Step 3: Trade CSV Parser (14-column format)
- **New:** `lib/dividendsomatic/portfolio/flex_trades_csv_parser.ex`
- Parses YYYYMMDD dates, classifies BUY/SELL and FX trades (EUR.SEK, EUR.HKD)
- Deterministic external_ids for re-import dedup
- **Mix task:** `mix import.flex_trades path/to/Trades.csv`
- **Context:** `Portfolio.import_flex_trades_csv/1` with broker+external_id upsert
- 12 tests

#### Step 4: Actions CSV Parser + Integrity Checker
- **New:** `lib/dividendsomatic/portfolio/flex_actions_csv_parser.ex`
- Parses two-section Actions.csv: BASE_SUMMARY totals + transaction detail rows
- Header-indexed parsing (44 columns, position-independent)
- **New:** `lib/dividendsomatic/portfolio/integrity_checker.ex`
- 4 reconciliation checks: dividends, trades, missing ISINs, summary totals
- Returns PASS/FAIL/WARN per check with discrepancy details
- **Mix task:** `mix check.integrity path/to/Actions.csv`
- 12 tests (7 parser + 5 integrity)

#### Step 5: Import Orchestrator + Worker Update
- **New:** `lib/dividendsomatic/data_ingestion/flex_import_orchestrator.ex`
- Scans directory, classifies each CSV, routes to correct pipeline
- Portfolio → snapshot, Dividends → dividend records, Trades → broker_transactions, Actions → integrity report
- Optional archive to `csv_data/archive/flex/`
- **Modified:** `workers/data_import_worker.ex` — uses `FlexImportOrchestrator` instead of `CsvDirectory`
- **Modified:** `bin/fetch_flex_email.sh` — searches 4 mailboxes (Activity Flex, Dividend Flex, Trades Flex, Actions Flex)

### Files Summary

| Action | Count | Files |
|--------|-------|-------|
| New modules | 6 | flex_csv_router, flex_dividend_csv_parser, flex_trades_csv_parser, flex_actions_csv_parser, integrity_checker, flex_import_orchestrator |
| New mix tasks | 3 | import_flex_div_csv, import_flex_trades, check_integrity |
| New migration | 1 | add_flex_dividend_fields (figi, gross_rate, net_amount, quantity_at_record, fx_rate) |
| New tests | 5 | flex_csv_router_test, flex_dividend_csv_parser_test, flex_trades_csv_parser_test, flex_actions_csv_parser_test, integrity_checker_test |
| Modified | 4 | portfolio.ex, dividend.ex, data_import_worker.ex, fetch_flex_email.sh |

### Quality
- 547 tests, 1 pre-existing failure (StockLive UI test), 0 new failures
- 0 credo issues (--strict)
- 0 compilation warnings
- Code formatted

### Usage
```bash
mix import.flex_div_csv new_csvs/Dividends.csv    # Import dividends
mix import.flex_trades new_csvs/Trades.csv         # Import trades
mix check.integrity new_csvs/Actions.csv           # Run integrity checks
```

---

# Previous Session — 2026-02-17 (Morning)

## Fix Missing IBKR Dividends & Data Recovery Pipeline

### Context
426 of 650 IBKR dividend transactions were not making it into the `dividends` table. Root cause: the `DividendProcessor` regex failed on "Payment in Lieu of Dividend" (PIL) records (no per-share amount in description) and Foreign Tax entries misclassified as dividends. Additionally, valuable data sat unprocessed in `csv_data/` subfolders (81 Yahoo JSON files, 6 Flex dividend CSVs).

### Pipeline Results (`mix process.data --all`)

| Step | Result |
|------|--------|
| Yahoo dividends | 0 new (5,709 already existed) |
| DividendProcessor | **51 new** (PIL total_net fallback) |
| Flex dividend CSVs | **22 new** from 6 files |
| Archive flex snapshots | 0 new (160 already imported) |
| **Total dividends** | **6,221** (up from 6,148, +73) |

### Quality
- 500 tests, 0 failures (up from 447)
- 0 credo issues (--strict)
