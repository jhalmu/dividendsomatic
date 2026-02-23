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

# Data maintenance
mix backfill.instruments             # Backfill currency + company data
mix backfill.instruments --currency  # Only currency
mix backfill.instruments --company   # Only company profiles
mix backfill.aliases                 # Split commas, set primary, fix base names
mix backfill.aliases --variants      # Also collect variant aliases from data tables
mix import.fx_rates                  # Import FX rates from all CSV sources
mix backfill.fx_rates                # Backfill fx_rate + amount_eur

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

**Version:** 0.40.0 (Production Live)
**Status:** Live at https://dividends-o-matic.com — full CI/CD pipeline, Gmail auto-import active
**Branch:** `main`

**Latest session (2026-02-23 Yield FX Mismatch Regression Tests & Audit Skill):**
- **3 yield FX regression tests** — same-currency (USD/USD), cross-currency (SEK/EUR), consistency invariant
- **yield-audit skill** — weekly checklist with reference values, formula docs, red flags table
- **EOD workflow updated** — weekly yield audit step added to CLAUDE.md
- Post-mortem: div_fx defaulted to 1.0 instead of pos.fx_rate, inflating USD yields ~17%
- 682 tests, 0 failures

**Previous session (2026-02-22 persistent_term Cache for Navigation):**
- **`persistent_term` caching** — wrapped 5 immutable query functions (chart data, first snapshot, count, costs) with `persistent_term` memoization
- **Navigation queries reduced** — ~12 DB queries per nav click → ~5 (8 queries eliminated after first load)
- **Derived values** — `has_prev`, `has_next`, `snapshot_position`, `total_snapshots` computed from cached chart data instead of 4 separate DB queries
- **Cache invalidation** — `invalidate_cache/0` called after snapshot import, activity import, and orchestrator import
- **Test isolation** — `Portfolio.invalidate_cache()` added to DataCase setup
- **Lighthouse audit** — Performance 84, Accessibility 100, Best Practices 100, SEO 100
- 679 tests, 0 failures

**Previous session (2026-02-22 Cash Flow Cleanup & Balance Check Fix):**
- **Cash flow dedup** — `mix dedup.cash_flows` removed 272 exact/description duplicates from overlapping Activity Statement imports
- **Cash flow cleanup** — `mix cleanup.cash_flows` removed 347 additional records:
  - 272 Nordnet records (TALLETUS, NOSTO, LAINAKORKO, nordnet-migrated data)
  - 93 currency-duplicate IBKR interest (same charge in both USD and EUR)
  - 12 variant-description duplicates ("Debit Interest for Debit Interest" style)
- **Interest corrected**: €32,963 → €18,316 (matches IBKR ground truth €18,165 within €151)
- **Realized P&L date-scoped**: only positions sold after IBKR start date; pre-NLV sales already reflected in NLV_start
- **Balance check improved**: 40.69% FAIL → **8.80% WARNING** (€7,583 gap)
- **Remaining gap sources**: missing Δ unrealized P&L (snapshot-only), untracked FX effects, €24k dividend gap vs IBKR
- 679 tests, 0 failures

**Previous session (2026-02-22 Production Deployment & Go-Live):**
- **Production live** — https://dividends-o-matic.com with Let's Encrypt TLS
- **CI/CD pipeline green** — all 5 jobs passing (quality/security/test/build/deploy)
- **Dockerfile** — multi-stage build (hexpm/elixir 1.19.5-erlang-28.3.2 + debian trixie-20260202-slim)
- **Docker Compose** — app + Postgres 17, external homesite_caddy network
- **Caddy reverse proxy** — shared with homesite, security headers, www redirect
- **Database restored** — pg_dump from dev → pg_restore to production
- **Gmail auto-import** — Google OAuth configured, Oban cron at 12:00 UTC Mon-Sat
- **CI fixes** — 6 issues fixed (OTP version, seeds schema, test DB, credo, Debian tag, npm)
- 679 tests, 0 failures

**Previous session (2026-02-21 Alias System — Base Names & Variants):**
- **`is_primary` flag on aliases**: 349/349 instruments have primary alias (finnhub > symbol_mapping > ibkr priority)
- **Comma-separated aliases split**: 12→0 (e.g., "TELIA1, TLS" → separate records)
- **49 instrument symbols fixed**: broker codes + company names → tickers (TELIA1→TELIA, "ALIBABA GROUP..."→BABA)
- **122 variant aliases collected**: 62 from positions + 59 from sold_positions + 1 from trades
- **Deterministic lookups**: dividend_validator + ibkr_activity_parser now ORDER BY is_primary DESC
- **Alias integrity checks**: instruments_without_primary_alias + comma_separated_aliases in schema_integrity
- **New task**: `mix backfill.aliases` (with `--dry-run`, `--variants`)
- 685 tests, 0 failures
- **Known issue**: `mix validate.data` crashes on nil amounts in find_outliers (pre-existing)

**Previous session (2026-02-21 ISIN Backfill & Symbol Unification):**
- **Canonical `symbol` on instruments**: 349/349 (100%) — from positions (178) + aliases (171)
- **Sold position ISIN backfill**: 1,252→4,817/6,291 (77%) — symbol→ISIN lookup with currency disambiguation
- **Currency backfill complete**: 349/349 (100%) — 13 remaining filled from trades+dividends
- **Sector/industry enrichment**: 39→187/349 (54%) — API fetch via Finnhub/Yahoo/EODHD
- **Display code updated**: `payment_symbol/1` prefers `instrument.symbol` over aliases
- **Integrity checks extended**: `null_instrument_symbol` (info), `null_sold_isin` escalated to warning
- **New task**: `mix backfill.sold_position_isins` (with `--dry-run`)
- **Extended task**: `mix backfill.instruments --symbol`
- 674 tests, 0 failures, no new credo issues

**Previous session (2026-02-21 Database Cleanup & Integrity):**
- **Dropped all 6 legacy tables**: legacy_holdings, legacy_portfolio_snapshots, legacy_symbol_mappings, legacy_dividends, legacy_broker_transactions, legacy_costs
- **4 migration tasks created**: `migrate.symbol_mappings` (34 resolved), `migrate.legacy_dividends` (15 new broker + 5,835 yfinance archived), `migrate.legacy_transactions` (3,818 trades, 25 dividends, 257 cash flows, 159 interest, 98 corporate actions), `migrate.legacy_costs` (158 interest)
- **Deleted 13 obsolete modules**: 6 schema files + 7 import tasks/processors referencing legacy schemas
- **SchemaIntegrity system**: 4 checks (orphan, null field, FK integrity, duplicate) in `schema_integrity.ex`
- **Oban IntegrityCheckWorker**: daily at 06:00 UTC
- **IntegrityChecker rewritten**: uses DividendPayment/Trade/Instrument instead of legacy schemas
- **DataGapAnalyzer rewritten**: uses DividendPayment/Trade instead of legacy schemas
- **SymbolMapper + Stocks rewritten**: uses InstrumentAlias instead of SymbolMapping
- **CSV/PDF archive**: 345MB zip at `../dividendsomatic_data_2026-02-21.zip`
- 666 tests, 0 failures, 0 credo warnings

**Previous session (2026-02-21 Legacy Instrument Merge):**
- **`mix merge.legacy_instruments`** — merged 24/29 LEGACY: instruments into proper counterparts, deduped 27 dividend_payments
- **Legacy schema cleanup** — rewrote 8 files from Dividend/BrokerTransaction to DividendPayment/Trade+Instrument joins
- **Deleted** `migrate_legacy_dividends.ex`, `compare_legacy.ex` (superseded by merge task)
- Positions view now shows dividend data (est_monthly, projected_annual, yield_on_cost)
- 716 tests, 0 failures, 12 pre-existing credo issues

**Previous session (2026-02-20 Balance Check Fix):**
- **NLV-based balance check** — validator uses net liquidation value for margin accounts instead of gross position_value/cost_basis
- **Initial capital fix** — NLV at start (€107k) instead of cost_basis (€389k) which included margin-funded positions
- **Current value fix** — NLV now (€86k) instead of position_value (€310k) which ignored -€264k margin loan
- **Unrealized P&L EUR-converted** — multiplied by position fx_rate (€2,525 EUR vs old mixed-currency €1,265)
- **Direct EUR dividend sum** — `SUM(COALESCE(amount_eur, net_amount))` = €83,871 vs pipeline €78,812 (recovered €5k zeroed by cross-currency fx_rate=0)
- **Margin-aware thresholds** — <5% pass, 5-20% warning, >20% fail (vs 1%/5% for cash accounts)
- Balance check: 12.13% FAIL → **16.30% WARNING** — honest NLV-based gap, remaining €14k from FX effects on cash balances
- 705 tests (3 new), 0 failures, 5 pre-existing credo issues

**Previous session (2026-02-20 FX Rates):**
- **fx_rates table** — 607 rate records, 9 currencies (USD, CAD, NOK, JPY, SEK, HKD, GBP, TRY, CHF), 2021-2026
- **FxRate schema + lookup** — `get_fx_rate/2` with nearest-preceding-date fallback, `upsert_fx_rate/1`
- **`mix import.fx_rates`** — imports from 163 Flex CSVs (FXRateToBase) + 8 Activity Statements (M2M Forex + Base Currency Exchange Rate)
- **`mix backfill.fx_rates`** — 840/841 dividends + 677/689 cash flows got fx_rate + amount_eur
- **EUR-aware aggregation** — `total_costs_by_type`, `total_deposits_withdrawals`, validator all use `COALESCE(amount_eur, amount)`
- **Activity parser extended** — `import_fx_rates` wired into `import_transactions` pipeline
- Interest costs: €39.6k → **€18.2k** (close to Lynx ground truth €21.8k)
- Fee costs: €3.1k → **€1.97k** (properly converted)
- Dividend total: €141.7k → **€78.8k** (841 IBKR records, honestly EUR-converted)
- Balance check gap: 12.13% (€37.6k) — wider because old inflated numbers no longer cancel; all figures now honest EUR
- 702 tests, 0 failures, 2 pre-existing credo suggestions

**Previous session (2026-02-20 cont.):**
- **Data Table Filling & Consolidation** — 5-phase plan fully implemented
- **Instrument currency backfill** — 336/336 instruments filled (trades → dividends → Flex CSVs → Activity CSVs → ISIN/exchange inference)
- **Activity Statement parser extended** — corporate actions (30), NAV snapshots (7), borrow fees (119)
- **Instrument enrichment** — 39 instruments got sector/industry/country from company_profiles via aliases join
- **`mix compare.legacy`** — diagnostic comparing legacy vs new tables (trades 7407→7663, dividends 6167→841 IBKR-only, costs distributed)
- **Balance check improved** — costs split into interest (€39.6k) / fees (€3.1k), cash balance (−€264k margin loan) exposed as informational
- **Migrations** — corporate_action fields (external_id, currency, proceeds) + instrument enrichment (sector, industry, country, logo_url, web_url)
- **Credo cleanup** — refactored `unless...else` → `if`, extracted helpers to reduce nesting depth
- Balance check gap: 8.77% (€27.2k) — FX effects and timing differences not yet accounted for
- 688 tests, 0 failures, 2 credo suggestions (cyclomatic complexity in parser)

**Previous session (2026-02-20):**
- **PortfolioValidator** — new module validating `current_value ≈ net_invested + total_return`
- **Balance check** — 1%/5% tolerance thresholds (pass/warning/fail), all components exposed
- **IBKR scoping** — realized P&L filtered to `source="ibkr"`, cash flows date-scoped after first IBKR Flex snapshot
- **Initial capital** — first IBKR Flex snapshot cost basis (€389k) used as implicit deposit for in-kind transfers
- **Integrated into `mix validate.data`** — formatted output + JSON export support
- **Gap reduced** from 185% → 8.58% (€26.6k remaining, likely FX/cash/dividend scope)
- 676 tests, 0 failures

**Previous session (2026-02-19 cont.):**
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
- FX rates table (607 records, 9 currencies, 2021-2026) with EUR conversion on dividends + cash flows
- 674 tests + 21 Playwright E2E tests, 0 credo warnings
- Multi-provider market data: Finnhub + Yahoo Finance + EODHD with fallback chains
- All instrument currencies populated (349/349), all symbols populated (349/349)
- Sold position ISIN coverage: 4,817/6,291 (77%)
- Corporate actions, NAV snapshots, borrow fees parsed from Activity Statements
- Legacy instrument merge (`mix merge.legacy_instruments`)
- **All 6 legacy tables dropped** — data migrated, schemas deleted, imports rewritten
- SchemaIntegrity system (5 checks: orphan, null field, FK integrity, duplicate, alias quality) + Oban daily worker
- Deterministic alias system: 567 aliases, 349 primary, is_primary flag + priority ordering
- 685 tests + 21 Playwright E2E tests, 0 credo warnings

**Next priorities:**
- Remaining 162 instruments without sector (delisted/unknown symbols — may need manual mapping)
- EODHD historical data backfill (30+ years available)

**Investigated & documented:**
- Balance check gap 8.80% (€7,583) — remaining gap from: (1) missing Δ unrealized P&L — we only have current snapshot, not starting unrealized at NLV_start, (2) untracked FX effects on multi-currency margin loan, (3) dividend gap €81k vs IBKR €105k (possibly missing PIL/withholding refunds). Would require period-start unrealized tracking or IBKR dividend reconciliation to close further.

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
- [x] Production deployment infrastructure (Dockerfile, CI/CD, Caddy) — live at dividends-o-matic.com
- [x] Chart reconstruction N+1 queries fixed (3,700+ → 3 queries + persistent_term cache)
- [x] Multi-provider market data architecture (Finnhub + Yahoo + EODHD)
- [x] IBKR dividend recovery: PIL fallback, Foreign Tax filter, 73 new dividends
- [x] Test coverage: 666 tests + 21 Playwright E2E
- [x] Data consolidation: all instrument currencies, corporate actions, NAV snapshots, borrow fees
- [ ] ~162 instruments missing company profiles (delisted/unknown symbols)
- [x] Historical prices: 53/63 stocks + 7 forex pairs fetched
- [x] Symbol resolution: 64 resolved, 44 unmappable, 0 pending

---

*Older session notes archived in [docs/ARCHIVE.md](docs/ARCHIVE.md)*
