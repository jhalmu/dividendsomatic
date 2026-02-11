# Session Report - 2026-02-11

## Summary
FX currency conversion, dynamic growth stats, dynamic market sentiment, yfinance dividend import tool, euro formatting, Gmail date fix. 218 tests, 0 failures, 0 credo issues.

## FX Currency Conversion
- Discovered 8 currencies in portfolio (EUR, USD, SEK, NOK, JPY, HKD, GBP, CAD)
- Applied `fx_rate_to_base` conversion in portfolio_live.ex (total_value, total_pnl)
- Applied in portfolio.ex (chart data, growth stats, calculate_total_value)
- Created `to_base_currency/2` helper in portfolio context
- Historical FX rates preserved per-holding per-snapshot (time machine accuracy)

## Dynamic Growth Stats
- `get_growth_stats/1` now accepts optional snapshot parameter
- Badge shows change from first snapshot to currently viewed snapshot (not always latest)
- Navigating between snapshots updates the growth badge dynamically

## Dynamic Market Sentiment
- Created `fear_greed_history` table and `FearGreedRecord` schema
- `fetch_and_store_history/1` fetches N days from Alternative.me API
- `get_fear_greed_for_date/1` with 3-day fallback for nearest date
- LiveView F&G gauge updates per snapshot date during navigation
- Stored 365 days of historical F&G data

## yfinance Dividend Import
- Created `tools/yfinance_fetch.py` Python side tool
- Exchange suffix mapping: HEX→.HE, TSEJ→.T, OSE→.OL, SBF→.PA, IBIS→.DE, SEHK→.HK
- SYMBOL_OVERRIDES for special cases (Finnish short codes, Oslo "o" suffix, HK zero-padding, Toronto .UN REITs)
- Created `lib/mix/tasks/import_yahoo.ex` for importing JSON output
- Imported 5,498 dividend records across 60+ symbols

## Euro Formatting
- Finnish convention: 1 234,56 € (non-breaking space separator, comma decimal)
- `format_euro_decimal/1`, `format_euro_signed/1`, `format_euro_number/2` helpers
- Applied throughout portfolio_live template

## Bug Fixes
- Gmail date parsing: DD/MM/YYYY (European) instead of MM/DD/YYYY (American)
- Chart line widths refined: value 2.5→1.5, cost basis 1.5→1

## Testing (218 tests, 0 failures)
- `fear_greed_record_test.exs` - schema validation, range, uniqueness
- `market_sentiment_history_test.exs` - date lookup, fallback, colors
- `portfolio_fx_test.exs` - FX conversion in charts, dynamic growth stats
- `import_yahoo_test.exs` - JSON import, duplicate handling
- Credo --strict: 0 issues

## Files Created
- `lib/dividendsomatic/market_sentiment/fear_greed_record.ex`
- `priv/repo/migrations/20260211164500_create_fear_greed_history.exs`
- `lib/mix/tasks/import_yahoo.ex`
- `tools/yfinance_fetch.py`
- `tools/requirements.txt`
- `test/dividendsomatic/market_sentiment/fear_greed_record_test.exs`
- `test/dividendsomatic/market_sentiment_history_test.exs`
- `test/dividendsomatic/portfolio_fx_test.exs`
- `test/dividendsomatic/import_yahoo_test.exs`

## Files Modified
- `lib/dividendsomatic_web/live/portfolio_live.ex` - Euro helpers, FX conversion, dynamic F&G
- `lib/dividendsomatic/portfolio.ex` - FX conversion, dynamic growth stats, to_base_currency
- `lib/dividendsomatic/market_sentiment.ex` - Historical F&G storage and lookup
- `lib/dividendsomatic_web/components/portfolio_chart.ex` - Thinner line widths
- `lib/dividendsomatic/gmail.ex` - DD/MM/YYYY date fix
- `test/dividendsomatic/gmail_test.exs` - Updated date format assertions
- `MEMO.md` - Session notes updated

## Remaining Open Issues
- #22 Multi-provider market data architecture (future)

---

# Session Report - 2026-02-10

## Summary
Full 6-phase evolution plan executed: UI overhaul with terminal theme, PostgreSQL migration, generic data ingestion pipeline, stock detail pages, market data research, comprehensive testing and quality improvements. 180 tests, 0 failures, 0 credo issues.

## Phase 1: UI Overhaul (#12-16)
- Template restructured: brand + stats + chart + compact nav + holdings + nav + dividends + footer
- Brand area with "sisu & dividends" tagline
- Compact nav bars with white SVG flourishes flanking date display
- Circular F&G arc gauge in stats row (replaced holdings count card)
- Stats cards with elevated opaque background + backdrop blur
- Tile grid background pattern (40x40px)
- Enhanced dividend visualization: area fill + cumulative orange line + dots + labels
- Chart animations: SVG path drawing (stroke-dashoffset), pulsing current-date marker
- White nav flourishes (changed from rose/pink)
- Removed rose decorative line from brand area
- Removed F&G bar and colored background from chart SVG

## Phase 2: PostgreSQL Migration (#17)
- Switched from ecto_sqlite3 to postgrex
- docker-compose.yml with PostgreSQL 18 Alpine
- Updated dev/test/runtime configs
- Fixed SQL fragments: strftime → to_char (3 occurrences)
- Enabled Oban with cron scheduling

## Phase 3: Generic Data Ingestion (#18-19)
- DataIngestion behaviour with `list_available/1`, `fetch_data/1`, `source_name/0` callbacks
- CsvDirectory adapter (scans directory, extracts dates from filenames)
- GmailAdapter (wraps existing Gmail module)
- DataImportWorker Oban job (cron: weekdays 12:00)
- mix import.batch Mix task for bulk CSV import
- Normalizer module for CSV parsing

## Phase 4: Stock Detail Pages (#20)
- /stocks/:symbol route with StockLive
- Company info, stock quote, holdings history, dividend history
- External links by exchange (Yahoo Finance, SeekingAlpha, Nordnet)
- Clickable symbols in holdings table

## Phase 5: Market Data Research (#21)
- docs/MARKET_DATA_RESEARCH.md: provider comparison (Finnhub, Alpha Vantage, Twelve Data, EODHD, etc.)
- Coverage matrix for Finnish, Japanese, HK, Chinese stocks
- Free tier comparison and recommendation

## Testing & Quality
- **180 tests, 0 failures** (expanded from 125)
- **63.81% coverage** (threshold: 60%)
- **4 Playwright a11y tests passing** (axe-core, 0 violations)
- **Credo --strict: 0 issues**
- **0 compiler warnings**
- WCAG AA contrast compliance (--terminal-muted: #8896ab)
- Design system fluid tokens applied across all components
- New test files: data_ingestion_test (34), stock_live_test (10), data_import_worker_test (4), import_batch_test (7)

## Files Modified
- `lib/dividendsomatic_web/live/portfolio_live.html.heex` - Full template restructure
- `lib/dividendsomatic_web/live/portfolio_live.ex` - Nav component, white flourishes
- `lib/dividendsomatic_web/components/portfolio_chart.ex` - Round F&G gauge, removed chart F&G bar/background, dead code cleanup
- `lib/dividendsomatic_web/components/core_components.ex` - Design token migration
- `lib/dividendsomatic_web/components/layouts.ex` - Design token migration
- `assets/css/app.css` - Tile background, opaque stats, white nav, chart animations, a11y fixes
- `assets/js/app.js` - ChartAnimation hook
- `lib/dividendsomatic/repo.ex` - PostgreSQL adapter
- `lib/dividendsomatic/portfolio.ex` - to_char SQL fragments
- `lib/dividendsomatic/application.ex` - Oban enabled
- `lib/dividendsomatic/data_ingestion.ex` - New: generic ingestion
- `lib/dividendsomatic/data_ingestion/*.ex` - New: adapters + normalizer
- `lib/dividendsomatic/workers/data_import_worker.ex` - New: Oban worker
- `lib/dividendsomatic_web/live/stock_live.ex` - New: stock detail page
- `lib/dividendsomatic_web/router.ex` - /stocks/:symbol route
- `lib/mix/tasks/import_batch.ex` - New: batch import task
- `mix.exs` - postgrex, test_coverage config
- `config/*.exs` - PostgreSQL + Oban config
- `docker-compose.yml` - New: PostgreSQL container
- `README.md` - Updated with all features
- `MEMO.md` - EOD workflow updated with linters

## Files Removed
- `PLAN_GMAIL_IMPORT.md`
- `PLAN_CONTINUATION.md`

## GitHub Issues Closed
#12, #13, #14, #15, #16, #17, #18, #19

## Remaining Open Issues
- #22 Multi-provider market data architecture (future)
