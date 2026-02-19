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
mix validate.data --suggest          # Suggest threshold adjustments
mix validate.data --export           # Export timestamped snapshot
mix validate.data --compare          # Compare vs latest snapshot
mix check.all                        # Unified integrity check
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

**Version:** 0.30.0 (E2E Tests + Accessibility)
**Status:** Clean IBKR-derived tables, legacy stubs cleaned up, 21 Playwright E2E tests, WCAG AA accessibility passing
**Branch:** `main`

**Latest session (2026-02-19 cont.):**
- **Legacy stub cleanup** — removed 10 compilation warnings, simplified 5 files
- **Playwright E2E tests** — 21 tests (8 portfolio page, 7 stock page, 4 accessibility, 2 contrast)
- **Accessibility fixes** — `prefers-reduced-motion` support, opaque surfaces, contrast fixes, ARIA labels
- **Root cause**: CSS `fade-in` animations at `opacity: 0` caused axe-core to compute wrong foreground colors
- 668 tests, 0 failures, 0 credo issues

**Previous session (2026-02-19):**
- **Database rebuild phases 0-5 complete** — clean tables from 7 IBKR Activity Statement CSVs
- **6 new tables**: instruments, instrument_aliases, trades, dividend_payments, cash_flows, corporate_actions
- **IBKR Activity Statement parser** — multi-section CSV parser with dedup
- **Query migration** — portfolio.ex rewired to query new tables via adapter pattern
- **Legacy archival** — old tables renamed with `legacy_` prefix, schemas updated
- **Test migration** — all 26 failures fixed, 668 tests passing
- 668 tests, 0 failures, 0 credo issues

**Previous session (2026-02-18 late night):**
- **Stat card rearrange** — Unrealized P&L + Dividends | Portfolio Value + Costs | Realized {year} | F&G
- **DividendAnalytics module** — extracted shared functions from StockLive into `Portfolio.DividendAnalytics`
- **Per-symbol dividends** — moved from StockLive into Portfolio context (holdings table columns)
- **`total_realized_pnl/1`** — year-filtered realized P&L for same-period card
- Removed projected dividends from stat card (noisy early in year)
- 626 tests, 0 failures, 0 credo issues

**Previous session (2026-02-18 night):**
- **Yahoo Finance profile provider** — cookie+crumb+quoteSummary for sector/industry data
- **Finnish stock profiles** — fallback chain: Finnhub → Yahoo → holdings data, with profile merging
- **Collapsible sections** — Dividends Received + Previous Positions with totals in headers
- **Company Info in header** — removed separate card, merged into price header
- **Chart rounding** — ApexCharts formatters (fi-FI locale), data rounded at serialization
- **Removed Recent Dividends** — duplicate of dividend history chart
- **Deleted 56 duplicate total_net records** — cross-source per_share/total_net duplicates
- 601 tests, 0 failures, 0 credo issues

**Previous session (2026-02-18 evening):**
- **FX currency conversion fix** — smart resolution: dividend fx_rate → position fx_rate (if currencies match) → fallback
- **Backfilled 63 total_net dividends** with fx_rate from position data (71→8 remaining)
- **Shares + Div Currency columns** in Dividends Received table
- **FX uncertainty UI** — cross-currency mismatches shown as `~amount?` and excluded from totals
- **`missing_fx_conversion` validator** — flags total_net non-EUR without fx_rate
- 601 tests, 0 failures, 0 credo issues

**Previous session (2026-02-18):**
- **DividendValidator automation** — post-import hook in DataImportWorker, EOD workflow step
- **`mix check.all`** — unified integrity check (validation + gap analysis)
- **Timestamped snapshots** — `--export` writes timestamped + latest, `--compare` shows trends
- **Threshold suggestions** — `--suggest` flag, 95th percentile analysis per currency
- **Claude skill** — `.claude/skills/data-integrity.md` for triage workflows
- 563 tests, 0 failures, 0 credo issues

**Previous session (2026-02-17 late night, cont.):**
- **Deep Space design** — ultra-deep bg (#06080D), glass-morphism cards, noise grain texture
- **Typography** — Instrument Sans + IBM Plex Mono (replacing DM Sans + JetBrains Mono)
- **Luminous colors** — sky #5EADF7, emerald #34D399, amber #FBBF24
- **Holdings promoted** — always visible above charts, tabs reduced to Income + Summary
- 547 tests, 0 failures, 0 credo issues

**Previous session (2026-02-17 late night):**
- **Dashboard redesign** — ApexCharts, three-zone layout, tab navigation, lazy assigns
- **Dark/light toggle** — theme switcher in branding bar
- 547 tests, 0 failures, 0 credo issues

**Previous session (2026-02-17 night):**
- **Gmail module rewrite** — handles all 4 IBKR Flex CSV types (Activity, Dividend, Trades, Actions)
- **IntegrityChecker** — `run_all_from_string/1` for Gmail-downloaded CSV data
- **OAuth2** — configured, published to production (no 7-day token expiry)
- **Bug fixes** — sender address, MM/DD/YYYY date parsing, StockLive stale metrics test
- 547 tests, 0 failures, 0 credo issues

**Previous session (2026-02-17 evening):**
- **Multi-CSV import pipeline** — FlexCsvRouter, FlexDividendCsvParser, FlexTradesCsvParser, FlexActionsCsvParser
- **Integrity checker** — 4 reconciliation checks (dividends, trades, ISINs, summary totals)
- **Import orchestrator** — auto-detect + route all CSV types, archive processed files
- **Bug fixes** — section boundary parsing, PIL summary, trade dedup
- 547 tests (up from 500)

**Previous session (2026-02-17 morning):**
- **IBKR dividend fix** — DividendProcessor PIL fallback (total_net), Foreign Tax filter, ISIN→currency map
- **Parsers** — IbkrFlexDividendParser, YahooDividendParser, `process.data` orchestrator
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
- ApexCharts interactive charts (portfolio area + dividend bar/line) with smooth animations
- Dark/light mode toggle with Nordic Warmth palette
- P&L Waterfall chart (deposits, dividends, costs, realized P&L by month)
- Investment summary card (deposits, P&L, dividends, costs, total return)
- Enhanced navigation: week/month/year jumps, date picker, chart presets
- Dividend diagnostics for IEx verification
- 668 tests + 21 Playwright E2E tests, 0 credo issues
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

- [x] Gmail integration: OAuth configured, app published to production, all 4 Flex types supported
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
