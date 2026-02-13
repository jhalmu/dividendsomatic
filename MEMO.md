# MEMO.md

Session notes and progress tracking for the Dividendsomatic project.

---

## EOD Workflow

When user says **"EOD"**: Execute immediately without confirmation:
1. Run linters and quality checks:
   - `mix compile --warnings-as-errors`
   - `mix format --check-formatted`
   - `mix credo --strict`
   - `mix sobelow --config`
2. Run `mix test.all` (precommit + credo)
3. Sync GitHub issues (`gh issue list/close/comment`)
4. Update this MEMO.md with session summary
5. Commit & push
6. Check that CI/CD pipeline is green -> if not, investigate and fix issues

---

## Quick Commands

```bash
# Development
mix phx.server              # Start server (localhost:4000)
mix import.csv path/to.csv  # Import CSV data
mix import.nordnet           # Import Nordnet CSV
mix import.nordnet --9a path # Import 9A tax report
mix import.ibkr              # Import IBKR CSV/PDF

# Historical data
mix fetch.historical_prices              # Full pipeline
mix fetch.historical_prices --resolve    # Only resolve symbols
mix fetch.historical_prices --dry-run    # Preview fetch plan

# Testing
mix test.all                # Full test suite + credo
mix precommit               # compile + format + test

# Database
mix ecto.reset              # Drop + create + migrate
```

---

## Project Info

**Domain:** dividends-o-matic.com

## Current Status

**Version:** 0.17.0 (Lynx 9A PDF Trade Import)
**Status:** 6,291 sold positions across all sources (2019-2026)

**Latest session (2026-02-13, NIGHT 2):**
- **Code review fixes for feature/automate-flex-import branch**
  - Fixed hardcoded Dropbox path in AppleScript → passes `$CSV_DIR` via `osascript` argument
  - Fixed `String.to_atom/1` on CSV headers → uses string keys throughout `import_lynx_9a.ex`
  - Extracted duplicate ISIN static map → shared `Portfolio.IsinMap` module
  - Fixed 3 credo nesting depth warnings (import_lynx_9a, backfill_isin phases 3&4)
  - Added deprecation note to `GmailImportWorker` (retained for manual use)
  - Added 21 unit tests for Lynx 9A import (date parsing, decimal math, dedup, format_pnl)
  - Added 4 tests for CsvDirectory.archive_file/2 (move, mkdir, error, filename)
- 451 tests, 0 failures, 0 credo issues

**Previous session (2026-02-13, LATE EVENING):**
- **Lynx 9A PDF trade extraction & import**
  - Extracted 7,163 trades from 9 Lynx/IBKR PDF files (9A Vero tax forms, 2019-2024)
  - Two extraction methods: pikepdf widget annotations (2019-2020, 2022-2024) and pdftotext (2021 lukittu PDFs)
  - Created `mix import_lynx9a` task with 553 name→ticker mappings (DB lookup + manual map)
  - Imported 4,666 sold positions (source: `lynx_9a`)
  - **2020 was completely missing** — now filled with 254 positions across 57 stocks
  - **2019 expanded** from 9 to 129 positions (added IBKR account U2299935)
  - 2021-2024: 4,292 lot-level trade details added
  - Grand total: 6,291 sold positions, P&L: -302,301 EUR across all sources
  - Also extracted summary CSV: `csv_data/archive/lynx_all_9a_trades.csv` (7,163 rows)
- 426 tests, 0 failures

**Previous session (2026-02-13, EVENING):**
- **Automated IBKR Flex CSV import pipeline**
  - `bin/fetch_flex_email.sh` — AppleScript email fetcher (Mail.app → csv_data/)
  - launchd plist — Mon-Fri 11:30 EET, extracts CSV attachments from Activity Flex mailbox
  - Archive step — CSVs moved to `csv_data/archive/flex/` after successful import
  - Oban cron updated to 12:00 EET, removed GmailImportWorker cron
  - Daily flow: IBKR email (10:14) → fetch script (11:30) → import+archive (12:00)
- 426 tests, 0 failures

**Previous session (2026-02-13, AFTERNOON):**
- **Realized P&L EUR conversion** — mixed-currency P&L values now converted to EUR
  - Added `realized_pnl_eur` + `exchange_rate_to_eur` columns to `sold_positions`
  - COALESCE fallback in all summary/total queries (graceful if backfill not run)
  - `mix backfill.sold_pnl_eur` task: diagnostic phase + conversion phase (--dry-run supported)
  - SoldPositionProcessor: FX lookup at import time for non-EUR positions
  - Nordnet 9A parser: explicit EUR fields
  - UI: "FX pending" badge when unconverted positions exist
  - All 7 currencies converted (HKD, CAD, SEK, JPY, NOK, USD, GBP) — 0 skipped
- **Housekeeping**
  - Added `.env.example` with all config keys
  - Updated `.gitignore` for `.DS_Store` and `/csv_data/`
- 426 tests, 0 failures, 0 credo issues

**Previous session (2026-02-13, NIGHT):**
- **CSV processing & archive** — imported all CSV data, verified DB completeness, archived files
  - IBKR: 7,699 transactions (all previously imported)
  - Flex: 159 portfolio snapshots (all previously imported)
  - Nordnet: 2,074 parsed, 104 new transactions
  - Nordnet 9A: 605 trades (all previously imported)
  - Archived all CSVs to `csv_data/archive/{ibkr,nordnet,flex,dividends}/`
- **Data gaps page fix & usability**
  - Deleted 104 bad Nordnet transactions (9A report parsed as regular CSV)
  - Fixed Nordnet importer to skip `9a-report*` files
  - Added ISIN validation filter (length >= 12) — 174 clean stocks, 0 garbage
  - Added IBKR transaction date range to broker coverage timeline (3 bars: Nordnet, IBKR Txns, IBKR Flex)
  - Show actual stock descriptions instead of ticker numbers
  - Search/filter for per-stock table (name, ISIN, symbol)
  - Sortable columns (name, gap days, brokers) with direction toggle
  - Nordnet-only / IBKR-only counts in summary (6 stats instead of 4)
  - Collapsible dividend gaps section
  - Broker badges + gap row highlighting
- DB totals: 159 snapshots, 3,930 holdings, 7,404 broker txns, 6,148 dividends, 6,291 sold positions, 4,598 costs
- 409 tests, 0 failures, 0 credo issues

**Previous session (2026-02-13, EVE):**
- **Multi-provider market data architecture (#22)**
  - `MarketData.Provider` behaviour with 6 callbacks (3 required, 3 optional)
  - `MarketData.Dispatcher` with configurable fallback chains per data type
  - **Finnhub provider** — extracted from stocks.ex (quotes, profiles, metrics, candles, forex, ISIN lookup)
  - **Yahoo Finance provider** — wrapped existing module (candles, forex only)
  - **EODHD provider** — new (quotes, candles, forex, company profiles)
  - Stocks context rewired as facade — zero breaking changes for callers
  - stocks.ex reduced from 798 to ~550 lines
  - Config: provider chains in config.exs, EODHD_API_KEY in runtime.exs
- 46 new tests (409 total), 0 credo issues

**Previous session (2026-02-13, PM):**
- **Phase 1:** Batch-loaded historical prices — 3,700+ queries → 3 queries
  - `batch_symbol_mappings/1`, `batch_historical_prices/3`, `batch_get_close_price/3` in Stocks context
  - Rewrote `get_reconstructed_chart_data/0` to use in-memory pricing after batch load
- **Phase 2:** Deduplicated dividend queries — ~25 queries → ~5 queries
  - `compute_dividend_dashboard/2` builds holdings map once, loads dividends once
  - Refactored `assign_snapshot/2` in LiveView to use single dashboard call
- **Phase 3:** `:persistent_term` cache for reconstructed chart data
  - Invalidated on import (nordnet, ibkr, csv, historical prices)
- 15 new tests covering batch functions + dividend dashboard + cache invalidation
- Fixed 2 credo issues (nesting depth, cyclomatic complexity)

**Previous session (2026-02-13, AM):**
- Yahoo Finance adapter for free historical OHLCV data (no API key needed)
- Enhanced SymbolMapper: Finnhub ISIN lookup + static Nordic/EU maps (64 resolved, 44 unmappable, 0 pending)
- Historical prices fetched: 53/63 stocks + 7 forex pairs via Yahoo Finance
- Chart reconstruction working: 417 points from 2017-03 to 2026-02
- Nordnet 9A tax report parser fixed and 605 trades imported (439 new sold positions)
- Sold positions grouped by symbol (274 symbols instead of 1625 individual rows)
- Imported new IBKR CSV data: 999 new transactions (2025-2026)

**Key capabilities:**
- Nordnet CSV Import + IBKR CSV/PDF Import + 9A Tax Report
- Historical price reconstruction (Yahoo Finance, 2017-2026 continuous chart)
- Batch-loaded chart pricing (3 queries instead of 3,700+, cached in persistent_term)
- Symbol resolution: ISIN → Finnhub/Yahoo via cascading lookup
- Dividend tracking (6,148 records across 60+ symbols)
- Finnhub financial metrics, company profiles, stock quotes
- Fear & Greed Index (365 days history)
- Costs system, FX exposure, sold positions (grouped), data gaps analysis
- Rule of 72 calculator, dividend analytics
- Custom SVG charts with era-aware gap rendering
- 451 tests + 13 Playwright E2E tests, 0 credo issues
- Multi-provider market data: Finnhub + Yahoo Finance + EODHD with fallback chains

**Next priorities:**
- Visual verification of optimized page load at localhost:4000
- EODHD historical data backfill (30+ years available)
- Production deployment

---

## GitHub Issues

| # | Title | Status |
|---|-------|--------|
| [#22](https://github.com/jhalmu/dividendsomatic/issues/22) | Multi-provider market data architecture | Done |

All issues (#1-#22) closed.

## Technical Debt

- [ ] Gmail integration needs OAuth env vars (`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`)
- [ ] Finnhub free tier: quotes work, candles return 403 (using Yahoo Finance instead)
- [ ] 10 stocks missing Yahoo Finance data (delisted/renamed)
- [ ] No production deployment (Hetzner via docker-compose)
- [x] Chart reconstruction N+1 queries fixed (3,700+ → 3 queries + persistent_term cache)
- [x] Multi-provider market data architecture (Finnhub + Yahoo + EODHD)
- [x] Test coverage: 426 tests + 13 Playwright E2E, 0 credo issues
- [x] Historical prices: 53/63 stocks + 7 forex pairs fetched
- [x] Symbol resolution: 64 resolved, 44 unmappable, 0 pending

---

*Older session notes archived in [docs/ARCHIVE.md](docs/ARCHIVE.md)*
