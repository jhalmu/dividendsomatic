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

**Version:** 0.13.0 (Yahoo Finance + 9A Tax Report + Chart Reconstruction)
**Status:** Full historical reconstruction pipeline operational

**Latest session (2026-02-13):**
- Yahoo Finance adapter for free historical OHLCV data (no API key needed)
- Enhanced SymbolMapper: Finnhub ISIN lookup + static Nordic/EU maps (64 resolved, 44 unmappable, 0 pending)
- Historical prices fetched: 53/63 stocks + 7 forex pairs via Yahoo Finance
- Chart reconstruction working: 417 points from 2017-03 to 2026-02 (~872ms)
- Nordnet 9A tax report parser fixed and 605 trades imported (439 new sold positions)
- Sold positions grouped by symbol (274 symbols instead of 1625 individual rows)
- Imported new IBKR CSV data: 999 new transactions (2025-2026)

**Previous session (2026-02-12):**
- IBKR PDF Parser via `pdftotext -layout` (1,565 transactions)
- IBKR CSV/PDF import pipeline (`mix import.ibkr`)

**Key capabilities:**
- Nordnet CSV Import + IBKR CSV/PDF Import + 9A Tax Report
- Historical price reconstruction (Yahoo Finance, 2017-2026 continuous chart)
- Symbol resolution: ISIN → Finnhub/Yahoo via cascading lookup
- Dividend tracking (5,498 records across 60+ symbols)
- Finnhub financial metrics, company profiles, stock quotes
- Fear & Greed Index (365 days history)
- Costs system, FX exposure, sold positions (grouped), data gaps analysis
- Rule of 72 calculator, dividend analytics
- Custom SVG charts with era-aware gap rendering
- 348 tests + 13 Playwright E2E tests, 0 credo issues

**Next priorities:**
- Visual verification of reconstructed chart at localhost:4000
- Optimize chart data generation (N+1 queries, ~872ms)
- Multi-provider market data architecture (#22)
- Production deployment

---

## GitHub Issues

| # | Title | Status |
|---|-------|--------|
| [#22](https://github.com/jhalmu/dividendsomatic/issues/22) | Multi-provider market data architecture | Open |

All other issues (#1-#21) closed.

## Technical Debt

- [ ] Gmail integration needs OAuth env vars (`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`)
- [ ] Finnhub free tier: quotes work, candles return 403 (using Yahoo Finance instead)
- [ ] Chart reconstruction N+1 queries (~872ms, could batch price lookups)
- [ ] 10 stocks missing Yahoo Finance data (delisted/renamed)
- [ ] No production deployment (Hetzner via docker-compose)
- [x] Test coverage: 348 tests + 13 Playwright E2E, 0 credo issues
- [x] Historical prices: 53/63 stocks + 7 forex pairs fetched
- [x] Symbol resolution: 64 resolved, 44 unmappable, 0 pending

---

*Older session notes archived in [docs/ARCHIVE.md](docs/ARCHIVE.md)*
