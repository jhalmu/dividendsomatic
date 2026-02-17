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

# Data pipeline
mix process.data --scan              # Report what would be processed
mix process.data --all               # Run full import pipeline
mix import.flex_div_csv path.csv     # Import Flex dividend CSV (11-col)
mix import.flex_trades path.csv      # Import Flex trades CSV (14-col)
mix check.integrity path.csv         # Check integrity vs Actions.csv
mix report.gaps                      # 364-day gap analysis
mix validate.data                    # Dividend data validation
mix check.sqlite                     # Check SQLite for unique data

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

**Version:** 0.21.0 (IBKR Dividend Recovery)
**Status:** Full dividend pipeline, 500 tests, 0 credo issues

**Latest session (2026-02-17):**
- **IBKR dividend fix** — DividendProcessor PIL fallback (total_net), Foreign Tax filter, ISIN→currency map
- **Schema** — `amount_type` field on dividends (per_share | total_net)
- **Parsers** — IbkrFlexDividendParser, YahooDividendParser
- **Import tasks** — `mix import.flex_dividends`, `import.yahoo_dividends`, `process.data` orchestrator
- **Analysis** — DataGapAnalyzer (364-day chunks), DividendValidator, `mix report.gaps`, `mix validate.data`
- **Data check** — `mix check.sqlite`, `scripts/extract_lynx_pdfs.py`, `mix import.lynx_data`
- Pipeline recovered 73 new dividends → 6,221 total, grand total 137K EUR
- 500 tests, 0 failures, 0 credo issues

**Previous session (2026-02-15 evening):**
- **Layout reorder** — Dividend chart moved above portfolio chart, recent dividends compact inline
- **Enhanced navigation** — `-1Y/-1M/-1W` buttons, date picker, `+1W/+1M/+1Y`, Shift+Arrow week jumps
- **Chart presets** — 1M/3M/6M/YTD/1Y/ALL range buttons alongside year filter
- **P&L Waterfall chart** — lazy-loaded stacked bars (deposits/dividends/costs/P&L) with cumulative line
- **Chart transitions** — `ChartTransition` JS hook with path morphing + CSS transitions for smooth navigation
- **Backend** — `get_snapshot_nearest_date/1`, `waterfall_data/0`, `costs_by_month/2`
- 447 tests, 0 failures, 0 credo issues

**Previous session (2026-02-15 morning):**
- Dividend chart labels — year-aware format
- Dividend diagnostics — `diagnose_dividends/0` for IEx verification
- Investment summary card
- Credo cleanup
- 447 tests, 0 failures, 0 credo issues

**Previous session (2026-02-14):**
- **Unified portfolio history schema redesign**
  - New `portfolio_snapshots` + `positions` tables (old tables renamed to `legacy_*`)
  - All data sources write precomputed totals at import time — no runtime reconstruction
  - `get_all_chart_data/0` is now a single query, no joins, no reconstruction
  - Separate dividend chart section, date slider, era-aware gap rendering
  - 31 files changed, migration task `mix migrate.to_unified`
- 447 tests, 0 failures, 0 credo issues

**Previous session (2026-02-13):**
- Code review fixes for automate-flex-import branch
- Lynx 9A PDF trade extraction & import (7,163 trades, 4,666 sold positions)
- Automated IBKR Flex CSV import pipeline (AppleScript + launchd + Oban)
- Realized P&L EUR conversion (7 currencies)
- CSV processing & archive, data gaps page improvements
- Multi-provider market data architecture (#22)
- Batch-loaded historical prices (3,700+ → 3 queries + persistent_term cache)
- Yahoo Finance adapter, enhanced SymbolMapper

**Key capabilities:**
- Nordnet CSV Import + IBKR CSV/PDF Import + 9A Tax Report
- Historical price reconstruction (Yahoo Finance, 2017-2026 continuous chart)
- Batch-loaded chart pricing (3 queries instead of 3,700+, cached in persistent_term)
- Symbol resolution: ISIN → Finnhub/Yahoo via cascading lookup
- Dividend tracking (6,221 records across 60+ symbols, 137K EUR total)
- Finnhub financial metrics, company profiles, stock quotes
- Fear & Greed Index (365 days history)
- Costs system, FX exposure, sold positions (grouped), data gaps analysis
- Rule of 72 calculator, dividend analytics
- Custom SVG charts with era-aware gap rendering + chart transitions
- P&L Waterfall chart (deposits, dividends, costs, realized P&L by month)
- Investment summary card (deposits, P&L, dividends, costs, total return)
- Enhanced navigation: week/month/year jumps, date picker, chart presets
- Dividend diagnostics for IEx verification
- 500 tests + 13 Playwright E2E tests, 0 credo issues
- Multi-provider market data: Finnhub + Yahoo Finance + EODHD with fallback chains

**Next priorities:**
- Cross-check: `net_invested + total_return ≈ current_value`
- Investigate 5,623 zero-income dividends (Yahoo historical, no matching positions)
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
- [x] IBKR dividend recovery: PIL fallback, Foreign Tax filter, 73 new dividends
- [x] Test coverage: 500 tests + 13 Playwright E2E, 0 credo issues
- [x] Historical prices: 53/63 stocks + 7 forex pairs fetched
- [x] Symbol resolution: 64 resolved, 44 unmappable, 0 pending

---

*Older session notes archived in [docs/ARCHIVE.md](docs/ARCHIVE.md)*
