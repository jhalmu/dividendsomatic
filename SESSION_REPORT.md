# Session Report — 2026-02-18 (Night)

## Yahoo Finance Provider, UI Polish, Chart Rounding

### Context
Finnish stocks (KESKOB, NESTE, SAMPO, AKTIA) had no company profiles because Finnhub free tier returns 403 for Helsinki Exchange. Also polished the stock detail page (collapsible sections, company info in header) and main page (chart number rounding, removed redundant Recent Dividends).

### Changes Made

#### Yahoo Finance Profile Provider (`yahoo_finance.ex`)
- Implemented cookie+crumb+quoteSummary API flow for sector/industry data
- `fc.yahoo.com` → extract Set-Cookie → `v1/test/getcrumb` → `v10/finance/quoteSummary?modules=assetProfile`
- Returns sector, industry, country, website
- Added to provider chain: Finnhub → Yahoo → Eodhd (`config.exs`)
- Extracted `extract_cookie/1` + `fetch_crumb/1` helpers (Credo nesting fix)

#### Finnish Stock Profile Fallback (`stock_live.ex`)
- `resolve_api_symbol/2` — resolves portfolio symbols (KESKOB) to API symbols (KESKOB.HE) via SymbolMapper
- `profile_from_holdings/1` — builds basic profile from IBKR position data (name, exchange, currency, country from ISIN)
- `merge_profile/2` — combines API profile with holdings fallback, preferring non-nil API values
- `upsert_profile` now preserves existing non-nil DB values when updating with partial API data (`stocks.ex`)

#### Stock Detail Page UI (`stock_live.html.heex`)
- **Collapsible sections** — Dividends Received and Previous Positions wrapped in `<details>` with totals in summary line
- **Section reorder** — Dividends Received → Previous Positions → Investment Notes → External Links
- **Company Info in header** — market_cap, currency, IPO date moved to header metadata; separate card removed
- **Previous Positions P&L** — total realized P&L in collapsed heading with gain/loss colors

#### Main Page (`portfolio_live.html.heex`, `portfolio_live.ex`, `apex_chart_hook.js`)
- **Removed Recent Dividends** — both inline summary and separate card (duplicated dividend history chart info)
- **Chart number rounding** — portfolio values rounded to integers, dividend values to 2 decimals
- **ApexCharts formatters** — y-axis shows rounded integers with € suffix, tooltips show 2 decimal places (fi-FI locale)

#### Data Cleanup
- Deleted 56 duplicate total_net dividend records via `priv/scripts/delete_duplicate_total_net.exs`
- Updated `.claude/skills/data-integrity.md` with cross-source duplicate knowledge + check #7

### Validation Summary (6,167 records)
- 107 issues: 20 info, 87 warning
- 8 missing_fx_conversion, 8 mixed_amount_types, 12 isin_currency_mismatch, 79 inconsistent_amount
- 0 invalid currencies, 0 suspicious amounts, 0 cross-source duplicates

### Files Changed

| Action | File |
|--------|------|
| Modified | `lib/dividendsomatic/market_data/providers/yahoo_finance.ex` — profile fetching via cookie+crumb API |
| Modified | `lib/dividendsomatic/stocks.ex` — nil-safe upsert, `merge_non_nil` helper |
| Modified | `lib/dividendsomatic_web/live/stock_live.ex` — API symbol resolution, profile merging, holdings fallback |
| Modified | `lib/dividendsomatic_web/live/stock_live.html.heex` — collapsible sections, company info in header |
| Modified | `lib/dividendsomatic_web/live/portfolio_live.ex` — chart data rounding |
| Modified | `lib/dividendsomatic_web/live/portfolio_live.html.heex` — removed Recent Dividends sections |
| Modified | `assets/js/hooks/apex_chart_hook.js` — number formatters for axes and tooltips |
| Modified | `config/config.exs` — Yahoo in profile provider chain |
| Modified | `.claude/skills/data-integrity.md` — check #7, cross-source duplicates |
| Modified | `test/*/yahoo_finance_test.exs` — updated profile test |
| Modified | `test/*/stock_live_test.exs` — updated for KESKOB.HE + collapsible sections |
| New | `priv/scripts/delete_duplicate_total_net.exs` — one-time cleanup script |

### Quality
- 601 tests, 0 failures, 0 credo issues

---

# Session Report — 2026-02-18 (Evening)

## Fix Dividend FX Currency Conversion + Backfill

### Context
Telia (SE ISIN, SEK dividends) showed +400€ for a 0.50 SEK per-share dividend — a ~10x inflation. The original plan targeted `total_net` amounts not applying `fx_rate`, but investigation revealed a deeper issue: the income calculation blindly used the position's `fx_rate` even when dividend currency != position currency (e.g. SEK dividend on EUR-listed FWB position with fx_rate=1.0).

### Root Cause (Expanded)
- **`total_net` path**: returned raw `amount` without any fx_rate conversion
- **`per_share` path**: used position fx_rate for currency conversion, but this only works when dividend currency matches position currency. For cross-currency cases (SEK dividend on EUR position), the position fx_rate (1.0) is for EUR→EUR, not SEK→EUR
- **Data gap**: most dividend records had `fx_rate: nil` — the field existed but was only populated for recent IBKR Flex imports

### Changes Made

#### Smart FX Resolution (`portfolio.ex` + `stock_live.ex`)
New `resolve_fx_rate` / `resolve_dividend_fx` with cascading logic:
1. Dividend's own `fx_rate` → use it (IBKR Flex records)
2. Dividend is EUR → fx = 1.0
3. Dividend currency matches position currency → use position's fx_rate (most USD/CAD/SEK stocks)
4. Cross-currency mismatch → fx = 0 in totals (portfolio.ex), marked `fx_uncertain` in UI (stock_live.ex)

Position tuples expanded from `{date, symbol, qty, fx_rate}` to `{date, symbol, qty, fx_rate, currency}`.

#### Shares Column + FX Uncertainty in UI (`stock_live.html.heex`)
- **Shares** column shows matched holding quantity from portfolio snapshots
- **Div Currency** column highlights non-EUR currencies with accent color
- Uncertain FX entries shown as `~400.0?` (dimmed) instead of `+400,00 €`, excluded from total

#### `missing_fx_conversion` Validator (`dividend_validator.ex`)
New validation added to `validate/0` pipeline — flags `total_net` non-EUR dividends where `fx_rate` is nil or 1.0.

#### FX Rate Backfill (`priv/scripts/backfill_fx_rate.exs`)
One-time script to populate `fx_rate` on 71 total_net dividends from matching position data:
- **63 updated** (USD→EUR ~0.84, CAD→EUR ~0.62, SEK→EUR ~0.089)
- **8 skipped** (NCZ, ACP, ECC, ORCC, AQN, NEP — old sold positions, no position history)

#### Tests
- 2 new tests in `portfolio_test.exs`: total_net with fx_rate, total_net without fx_rate
- 5 new tests in `dividend_validator_test.exs`: missing_fx_conversion scenarios
- Updated `insert_test_holding` helper to accept currency parameter
- Fixed AAPL test: position currency changed from EUR to USD to match dividend currency

### Validation Summary (6,223 records)
- 118 issues: 30 info, 88 warning
- 9 missing_fx_conversion (down from 71), 19 mixed_amount_types, 11 isin_currency_mismatch, 79 inconsistent_amount
- 0 invalid currencies, 0 suspicious amounts, 0 cross-source duplicates

### Files Changed

| Action | File |
|--------|------|
| Modified | `lib/dividendsomatic/portfolio.ex` — smart FX resolution, position currency in tuples |
| Modified | `lib/dividendsomatic_web/live/stock_live.ex` — smart FX, fx_uncertain flag, matched_quantity |
| Modified | `lib/dividendsomatic_web/live/stock_live.html.heex` — Shares + Div Currency columns, FX uncertainty UI |
| Modified | `lib/dividendsomatic/portfolio/dividend_validator.ex` — missing_fx_conversion check |
| Modified | `test/dividendsomatic/portfolio_test.exs` — total_net tests, currency param |
| Modified | `test/dividendsomatic/portfolio/dividend_validator_test.exs` — missing_fx_conversion tests |
| New | `priv/scripts/backfill_fx_rate.exs` — one-time FX rate backfill |

### Remaining Edge Cases
- 8 total_net dividends without position data (old sold positions)
- BHP GBp/GBP mismatch (pence vs pounds — needs unit conversion)
- Telia SEK per_share on EUR position (needs SEK→EUR rate from external source)
- ~64 per_share cross-currency dividends (NOK/SEK/CAD/HKD on EUR positions)

### Quality
- 601 tests, 0 failures, 0 credo issues

---

# Session Report — 2026-02-18

## DividendValidator Automation, Learning & Skill

### Context
The DividendValidator had 6 checks and worked well, but was only invoked manually via `mix validate.data`. This session automated it (post-import, EOD), added threshold discovery, trend tracking, and a Claude skill for data integrity triage.

### Changes Made

#### Post-Import Validation Hook
- `DataImportWorker` now calls `DividendValidator.validate()` after successful imports
- Logs warning with issue count and severity breakdown if any issues found
- No blocking — log-level only

#### EOD Workflow Update
- `CLAUDE.md` EOD now includes `mix validate.data` as step 2
- Validation summary included in SESSION_REPORT.md
- `mix validate.data` and `mix check.all` added to allowed commands

#### `mix check.all` — Unified Integrity Command
- New mix task combining dividend validation + gap analysis in one pass
- Prints combined summary with total findings

#### Timestamped Snapshots & `--compare`
- `--export` writes timestamped files (`validation_20260218T...json`) + overwrites `validation_latest.json`
- `--compare` diffs current state vs latest snapshot (records, issues, severity trends)
- Timestamp field added to exported JSON

#### Threshold Suggestions (`--suggest`)
- New `suggest_threshold_adjustments/0` in DividendValidator
- Groups flagged items by currency, computes 95th percentile * 1.2 for currencies with 3+ flags
- `mix validate.data --suggest` prints suggestions

#### Claude Skill
- `.claude/skills/data-integrity.md` — all 6 checks documented with triage steps
- Currency threshold reference table
- Known false-positive patterns (IE ISINs paying USD, BDC special dividends)
- Instructions for adding new rules

### Validation Summary (6,223 records)
- 109 issues: 30 info, 79 warning
- 19 mixed_amount_types, 11 isin_currency_mismatch, 79 inconsistent_amount
- 0 invalid currencies, 0 suspicious amounts, 0 cross-source duplicates

### Files Changed

| Action | File |
|--------|------|
| Modified | `lib/dividendsomatic/workers/data_import_worker.ex` |
| Modified | `lib/dividendsomatic/portfolio/dividend_validator.ex` |
| Modified | `lib/mix/tasks/validate_data.ex` |
| Modified | `CLAUDE.md` |
| New | `lib/mix/tasks/check_all.ex` |
| New | `.claude/skills/data-integrity.md` |
| Modified | `test/dividendsomatic/portfolio/dividend_validator_test.exs` |
| Modified | `test/dividendsomatic/workers/data_import_worker_test.exs` |

### Quality
- 563 tests, 0 failures, 0 credo issues

---

# Session Report — 2026-02-17 (Late Night, cont.)

## Dashboard Redesign — "Deep Space" Final Polish

### Context
Continued refining the dashboard design. User disliked the warm brown/stone palette — shifted first to cool slate, then applied the frontend-design skill for a complete "Deep Space" aesthetic overhaul. Also moved Holdings section to be always visible above charts.

### Changes Made

#### Color Iterations
1. **Cool slate** — Replaced warm stone (#1C1917) with dark slate (#0B0F14), cool blue-grey borders/text
2. **Deep Space** — Ultra-deep background (#06080D), glass-morphism surfaces with backdrop-filter blur, subtle SVG noise grain texture, radial glow accent

#### Typography
- **Instrument Sans** (geometric display font) replacing DM Sans
- **IBM Plex Mono** (authoritative data font) replacing JetBrains Mono

#### Visual Effects
- Glass-morphism cards: translucent `rgba(14, 18, 27, 0.85)` + `backdrop-filter: blur(16px)`
- Subtle noise grain texture overlay (`opacity: 0.025`)
- Radial glow at top center for depth
- Luminous data colors: sky `#5EADF7`, emerald `#34D399`, amber `#FBBF24`
- Softer P&L: emerald gains, coral losses (vs harsh green/red)

#### Layout
- Holdings section promoted above Portfolio Performance chart (always visible)
- Tab strip reduced to Income + Summary only
- Default active tab changed to Income

### Quality
- 547 tests, 0 failures, 0 credo issues

---

# Session Report — 2026-02-17 (Late Night)

## Dashboard Redesign — Nordic Warmth + ApexCharts

### Context
The dashboard had grown organically with a terminal/hacker aesthetic (scanlines, green-on-black). The user designed a "Photo Album" concept — warm, organic, approachable — with interactive charts and a focused layout. Full 4-phase redesign implemented.

### Changes Made

#### Phase 1: Visual Foundation
- **Nordic Warmth palette** — warm stone colors (oklch values) replacing cold terminal greens
- **DaisyUI themes** — dark (default) + light mode with warm tones
- **Three-zone layout**: The Day (sticky date nav + stats), The Journey (charts), The Details (tabs)
- **Tab navigation** — Holdings/Income/Summary with lazy-loaded content
- Removed scanline overlay and grid texture
- Updated all pages: portfolio, stock detail, data gaps

#### Phase 2: ApexCharts Integration
- **Installed** `apexcharts` npm package
- **New:** `assets/js/hooks/apex_chart_hook.js` — generic LiveView ↔ ApexCharts hook
- **New:** `assets/js/chart_configs/portfolio.js` — area chart (value + cost basis, gradient fill, datetime axis)
- **New:** `assets/js/chart_configs/dividend.js` — bar+line (monthly + cumulative, dual y-axis)
- **Server-side config builders** — `build_portfolio_apex_config/1`, `build_dividend_apex_config/1`
- **Data serialization** — `serialize_portfolio_chart/2`, `serialize_dividend_chart/1`
- **push_event** updates on chart range change
- Removed old ChartAnimation/ChartTransition hooks

#### Phase 3: Lazy Assigns
- Summary tab data (P&L, FX exposure, investment summary) deferred until tab activation
- `maybe_load_summary/1` auto-loads when navigating while already on Summary tab

#### Phase 4: Polish
- **Dark/light mode toggle** button in branding bar
- Holdings section moved above Portfolio Performance chart (always visible, not in tabs)
- Tab strip reduced to Income + Summary

### Files Summary

| Action | Count | Files |
|--------|-------|-------|
| Modified | 8 | app.css, app.js, portfolio_live.ex, portfolio_live.html.heex, root.html.heex, stock_live.html.heex, data_gaps_live.html.heex, portfolio_live_test.exs |
| New | 3 | apex_chart_hook.js, chart_configs/portfolio.js, chart_configs/dividend.js |
| Modified | 2 | package.json, package-lock.json |

### Quality
- 547 tests, 0 failures, 0 credo issues
- 0 compilation warnings
- Code formatted

---

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
