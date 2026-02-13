# Session Archive

Archived session notes from Dividendsomatic development. See [MEMO.md](../MEMO.md) for current status.

---

## 2026-02-13 - Yahoo Finance, 9A Tax Report & Chart Reconstruction

### Session Summary

Added Yahoo Finance adapter for free historical OHLCV data (Finnhub free tier doesn't support candles). Enhanced SymbolMapper with Finnhub ISIN lookup and static Nordic/EU symbol maps. Fixed Nordnet 9A tax report parser and imported 605 realized trades. Grouped sold positions display by symbol. Full chart reconstruction pipeline operational (2017-2026).

### Features
1. **Yahoo Finance Adapter** - HTTP adapter for chart API v8, no API key needed
2. **Symbol Resolution** - Finnhub ISIN lookup + static maps: 64 resolved, 44 unmappable, 0 pending
3. **Historical Prices** - 53/63 stocks + 7 forex pairs fetched via Yahoo Finance
4. **9A Tax Report** - Fixed parser column detection, imported 605 trades (439 new sold positions)
5. **Sold Positions Grouped** - 274 symbol summaries instead of 1625 individual rows
6. **Chart Reconstruction** - 417 data points from 2017-03 to 2026-02 (~872ms)

### Test Results
- 348 tests, 0 failures (17 excluded)
- Credo --strict: 0 issues

---

## 2026-02-12 (late) - IBKR PDF Parser

### Session Summary

Built IBKR PDF parser for Transaction History PDFs via `pdftotext -layout`. Two-pass type detection, amount-based correction, multi-word symbol extraction, ISIN handling. All 3 IBKR PDFs parsed: 1,565 transactions.

### Test Results
- 348 tests, 0 failures (17 excluded)
- Credo --strict: 0 issues

---

## 2026-02-12 - Nordnet CSV Import, Costs System & Data Gaps Page

### Session Summary

Full Nordnet CSV import pipeline with transaction parsing, broker_transactions table, derived dividends/sold positions/costs via processors, `mix import.nordnet` task, and Data Gaps analysis page. 62 new tests (348 total), 0 failures, Credo clean.

### Features
1. **NordnetCsvParser** - Tab-separated CSV parser for Nordnet transaction exports (Finnish column names, comma decimals)
2. **BrokerTransaction schema** - Unified broker transaction storage with upsert (idempotent by broker+external_id)
3. **DividendProcessor** - Derives dividend records from OSINKO transactions, cross-broker dedup by ISIN+date
4. **SoldPositionProcessor** - Derives sold positions from MYYNTI transactions, back-calculates purchase price from P&L
5. **CostProcessor** - Extracts commissions, withholding taxes, loan interest as cost records
6. **mix import.nordnet** - Mix task for importing Nordnet CSV files (single file or directory)
7. **Data Gaps Page** (/data/gaps) - Broker coverage timeline, per-stock gap analysis, dividend coverage gaps, current-holdings filter
8. **ISIN fields** - Added isin column to dividends and sold_positions for cross-broker deduplication

### Test Results
- 348 tests, 0 failures (17 excluded)
- 62 new tests across 8 test files
- Credo --strict: 0 issues

---

## 2026-02-12 - Finnhub Financial Metrics & Sector Badges

### Session Summary

Added Finnhub financial metrics (P/E, ROE, ROA, margins, debt/equity, payout ratio, beta) to stock detail pages with 7-day caching. Added sector/industry/country badges under company name. Created 9 Playwright E2E tests for stock pages. 286 tests + 9 Playwright, 0 failures, Credo clean.

### Features
1. Financial Metrics card with conditional color coding (data-driven thresholds)
2. Sector/industry/country/exchange badges in stock header
3. Playwright E2E test suite for stock pages (structure, badges, metrics, a11y)

### Test Results
- 286 tests, 0 failures (8 excluded)
- 9 Playwright E2E tests passing
- Credo --strict: 0 issues

---

## 2026-02-12 - IBKR API & Nordnet API Research

### Session Summary

Comprehensive research on IBKR API integration options (Client Portal API, TWS API, Web API), the Elixir `ibkr_api` hex package, user's existing Python implementations, and Nordnet API. Concluded that IBKR Client Portal API is not suitable for headless production deployment.

### Key Decision

**CSV import remains the primary data source.** The IBKR Client Portal API requires manual browser login and a Java gateway on the same machine - incompatible with headless Hetzner VPS deployment. 12 security/architecture red flags identified.

---

## 2026-02-12 - Phase 5B: Costs, Cash Flows & Short Positions

### Session Summary

Implemented all 6 features from Phase 5B plan. Code reviewed and all issues resolved. 17 new tests (276 total).

### Features
1. Enhanced Cost Basis (return %, P&L/share, break-even on stock page)
2. Cost Basis Evolution (dashed line on price chart)
3. FX Exposure Breakdown (currency table on portfolio page)
4. Realized P&L Display (sold positions table on both pages)
5. Cash Flow Summary (monthly dividend bar chart + cumulative table)
6. Short Position Support (SHORT badge, negative quantity handling)

### Test Results
- 276 tests, 0 failures (8 excluded)
- Credo --strict: 0 issues

---

## 2026-02-11 - Rule of 72 & Dividend Income Fix (Phase 4)

### Session Summary

Implemented Phase 4 (Rule of 72 calculator) on stock detail page and fixed dividend income calculation bug.

### Test Results
- 257 tests, 0 failures (8 excluded)
- Credo --strict: 0 issues

---

## 2026-02-11 - Company Notes & Dividend Analytics (Phase 2 + 3)

### Session Summary

Completed Phase 2 (Company Information) and Phase 3 (Dividend Calculations & Charts).

### Test Results
- 251 tests, 0 failures (5 excluded)
- Credo --strict: 0 issues

---

## 2026-02-11 - CSV Pipeline Hardening (Phase 1)

### Session Summary

Replaced positional CSV parsing with header-based parsing, added ISIN-based identifier strategy, holdings deduplication, and re-import tooling.

### Test Results
- 201 tests, 0 failures (5 excluded)
- Credo --strict: 0 issues

---

## 2026-02-10 - Evolution Plan Complete (Phases 1-5)

### Session Summary

Executed full 6-phase evolution plan: UI overhaul, PostgreSQL migration, generic data ingestion, stock detail pages, market data research, and comprehensive testing/quality improvements.

### GitHub Issues Closed
#12, #13, #14, #15, #16, #17, #18, #19

---

## 2026-02-10 - Testing Suite & Accessibility (#5, #9, #11)

### Session Summary

Major test coverage expansion (69 → 125 tests), Playwright + axe-core a11y testing setup, WCAG accessibility fixes.

---

## 2026-02-06 - Frontend Redesign, Tests & Quality

### Session Summary

Major frontend overhaul with combined charts, seed data improvements, test coverage expansion, and credo/DSG compliance.

---

## 2026-01-30 (evening) - GitHub Issues & Cleanup

Created GitHub issues for project roadmap, fixed compiler warnings, updated README.

---

## 2026-01-30 - Dependencies Update & Cleanup

Updated project dependencies to match homesite, added dev/test quality tools, cleaned documentation.

---

## 2026-01-29 - MVP Complete

Built complete MVP: CSV import, LiveView viewer, navigation, DaisyUI styling.
