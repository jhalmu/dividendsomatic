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

**Version:** 0.16.0 (EUR Currency Conversion for Realized P&L)
**Status:** P&L totals now correctly converted to EUR across all currencies

**Latest session (2026-02-13, AFTERNOON):**
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
- DB totals: 159 snapshots, 3,930 holdings, 7,404 broker txns, 6,148 dividends, 1,625 sold positions, 4,598 costs
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
- 426 tests + 13 Playwright E2E tests, 0 credo issues
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
