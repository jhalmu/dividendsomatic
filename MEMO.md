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

**Version:** 0.12.0 (IBKR PDF Parser + Historical Reconstruction)
**Status:** All phases complete including IBKR PDF import

**Latest session (2026-02-12 late night):**
- IBKR PDF Parser: parses Transaction History PDFs via `pdftotext -layout`
  - Two-pass type detection (date-line tokens → context fallback)
  - Amount-based correction for foreign_tax/dividend misclassification
  - Multi-word symbol extraction, ISIN extraction with line-break handling
  - Noise line filtering, description truncation to 255 chars
- Updated `mix import.ibkr` to handle both CSV and PDF files
- Enhanced SoldPositionProcessor with JSONB ticker fallback matching
- Added fallback PDF regex in DividendProcessor for interleaved descriptions
- Fixed 3 credo issues (cyclomatic complexity, redundant with clause)
- All 3 IBKR PDFs parsed: 1,565 transactions (2019-2025)

**Key capabilities:**
- Nordnet CSV Import + IBKR CSV/PDF Import
- Historical price reconstruction (2017-2022 Nordnet era)
- Dividend tracking (5,498 records across 60+ symbols)
- Finnhub financial metrics, company profiles, stock quotes
- Fear & Greed Index (365 days history)
- Costs system, FX exposure, sold positions, data gaps analysis
- Rule of 72 calculator, dividend analytics
- Custom SVG charts with era-aware rendering
- 348 tests + 13 Playwright E2E tests, 0 credo issues

**Next priorities:**
- Run `mix fetch.historical_prices` to populate historical data
- Visual verification of reconstructed chart at localhost:4000
- Phase 5A: GetLynxPortfolio automation
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
- [ ] Finnhub integration needs API key (`FINNHUB_API_KEY`)
- [ ] No production deployment (Fly.io or similar)
- [x] Test coverage: 348 tests + 13 Playwright E2E, 0 credo issues

---

*Older session notes archived in [docs/ARCHIVE.md](docs/ARCHIVE.md)*
