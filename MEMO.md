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

**Version:** 0.19.0 (Investment Summary & Dividend Diagnostics)
**Status:** Unified portfolio history, 447 tests, 0 credo issues

**Latest session (2026-02-15):**
- **Dividend chart labels** — replaced month-only X-axis labels ("01", "02") with year-aware format ("Jan 23", "Jul 24" for ≤24 months; compact "'24"/"M24" for >24 months)
- **Dividend diagnostics** — added `diagnose_dividends/0` for IEx verification (ISIN duplicates, zero-income records, top 20 by value, yearly totals)
- **Investment summary** — new card showing Net Invested, Realized/Unrealized P&L, Total Dividends, Total Costs, Total Return
  - `total_deposits_withdrawals/0` queries broker transactions with FX conversion
  - `investment_summary/0` combines all financial metrics
- **Credo cleanup** — merged chained Enum.filter, cond→if refactor, pattern match guard
- Merged `feature/separate-dividend-chart` → `main`
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
- Dividend tracking (6,148 records across 60+ symbols)
- Finnhub financial metrics, company profiles, stock quotes
- Fear & Greed Index (365 days history)
- Costs system, FX exposure, sold positions (grouped), data gaps analysis
- Rule of 72 calculator, dividend analytics
- Custom SVG charts with era-aware gap rendering
- Investment summary card (deposits, P&L, dividends, costs, total return)
- Dividend diagnostics for IEx verification
- 447 tests + 13 Playwright E2E tests, 0 credo issues
- Multi-provider market data: Finnhub + Yahoo Finance + EODHD with fallback chains

**Next priorities:**
- Run `diagnose_dividends()` to verify dividend totals
- Cross-check: `net_invested + total_return ≈ current_value`
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
