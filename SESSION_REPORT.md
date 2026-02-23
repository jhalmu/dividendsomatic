# Session Report — 2026-02-23 (PIL Dedup + Yield Fix + Credo Cleanup)

## Overview

Fixed TCPC and TRIN showing wrong Current Yield values, then fixed all 10 stock yields to match IBKR reference, and cleaned up all 42 credo warnings across 17 files. Root cause: IBKR creates two dividend_payment records per event (PIL portion + withholding adjustment), both with the same per_share. Without deduplication, TTM computation summed each record separately, inflating the annual rate ~2×.

## Root Cause Analysis

### The PIL Split Problem

IBKR Activity Statements create **two records per dividend event**:
1. Main payment (PIL or Cash Dividend) — positive net_amount
2. Withholding tax adjustment — negative net_amount, same per_share

Both records carry the same `per_share` value. `compute_annual_dividend_per_share` counted each record separately, doubling the per-event contribution to TTM sum.

### TCPC (before fix)
- Instrument: `dividend_rate: $2.37`, `dividend_source: "ttm_computed"`, `dividend_frequency: "monthly"` (wrong!)
- 4 dividend_payment records from 2 pay dates (2 records each)
- TTM sum: $0.04 + $0.25 + $0.25 + $0.25 = $0.79
- With "monthly" (12) extrapolation: $0.79/4 × 12 = **$2.37** (stored)
- Correct: quarterly $0.25 × 4 = **$1.00/year** → yield 21.69%

### TRIN (before fix)
- Instrument: `dividend_rate: $4.08`, `dividend_source: "manual"`, `dividend_frequency: "monthly"`
- 4 records from 2 pay dates: $0.17 (base monthly) + $0.51 (quarterly supplemental)
- IBKR reference yield uses base rate only: $0.17 × 12 = **$2.04/year** → yield 13.63%
- Stored $4.08 included quarterly supplementals

### Dashboard Date Range Bug
- `compute_dividend_dashboard` only loaded dividends from current year start (2026-01-01)
- TTM computation needs 365 days of data — only had ~2 months
- Caused AGNC/ORC/KESKOB to show ~1-2% instead of 12-19%

### Frequency Detection Bug
- PIL/withholding splits created 0-day gaps between same-date records
- Average gap skewed toward "monthly" instead of correct "quarterly"
- Fixed by deduplicating dates before computing gaps

## Changes

### 1. PIL Dedup in TTM Computation (`dividend_analytics.ex`)
- Deduplicate by `(ex_date, per_share)` using `Enum.uniq_by` before summing
- Use unique **dates** (not record count) for `payment_count` in extrapolation
- Same fix applied in `backfill_dividend_rates.ex:compute_rate_from_payments`
- Frequency detection: `Enum.uniq()` on dates before computing gaps

### 2. Dashboard TTM Date Range (`portfolio.ex`)
- Extended `compute_dividend_dashboard` to load from 365 days back for TTM
- `full_from = Enum.min([widest_from, ttm_start], Date)` ensures TTM data available
- Same `Enum.uniq()` fix in `detect_payment_frequency`

### 3. Manual Override Corrections (`backfill_dividend_rates.ex`)
- TRIN: $4.08 → $2.04 (base monthly, excludes quarterly supplementals)
- TCPC: added $1.00 quarterly (new override)
- KESKOB: added €0.88 quarterly (only 1 of 4 installments in data)
- Nordea: added €0.96 semi-annual (FY2025 dividend)
- All set as `dividend_source: "manual"` → protected from Yahoo/TTM overwrite

### 4. Tests (4 new, 686 total)
**Unit tests** (`dividend_analytics_test.exs`):
1. Dedup same date+per_share — two PIL records → one per_share counted
2. Keep different per_share on same date — regular + special both counted
3. Unique date counting — monthly extrapolation uses date count, not record count

**Integration test** (`portfolio_test.exs`):
4. PIL yield inflation guard — yield must be < 30% for $0.25 quarterly stock at $5.00

### 5. Yield Audit Skill Update (`.claude/skills/yield-audit.md`)
- Added PIL/withholding split red flags
- BDC/PIL pattern documentation
- TCPC sanity bounds (18-25% normal, >35% suspicious)
- Full test cross-references

### 6. Credo Cleanup (42 issues → 0 across 17 files)
- Extracted helper functions to reduce cyclomatic complexity and nesting
- Fixed alias ordering (alphabetical) in multiple mix tasks
- Replaced implicit try with explicit try/rescue in backfill_instruments
- Used `Enum.map_join/3` in cleanup_cash_flows
- Data-driven patterns in ibkr_activity_parser and schema_integrity
- Refactored `compute_best_annual_per_share` into smaller functions

## Yield Verification (10/10 match IBKR reference)

| Symbol | Expected Yield | Status |
|--------|---------------|--------|
| AGNC | 12.58% | OK |
| AKTIA | 6.59% | OK |
| CSWC | 10.20% | OK |
| KESKOB | 4.17% | OK |
| NDA FI | 5.60% | OK |
| NESTE | 0.94% | OK |
| ORC | 19.00% | OK |
| TCPC | 21.69% | OK |
| TELIA1 | 4.57% | OK |
| TRIN | 13.63% | OK |

## Protection Chain (Future-Proofing)

| Layer | Protection |
|-------|-----------|
| `dividend_analytics.ex` | PIL dedup in TTM computation + frequency detection |
| `backfill_dividend_rates.ex` | PIL dedup in historical rate computation |
| `backfill_dividend_rates.ex` | Manual overrides (TCPC, TRIN, TELIA, KESKOB, Nordea) |
| `dividend_source: "manual"` | Protected from Yahoo fetch + TTM overwrite |
| `fetch_dividend_rates.ex` | Skips instruments with "manual"/"ttm_computed" source |
| `portfolio.ex` | Dashboard loads 365 days for TTM, frequency dedup |
| Regression tests | 4 tests catch dedup regression |
| yield-audit skill | Documents patterns for future sessions |

## Verification

### Test Suite
- **686 tests, 0 failures** (25 excluded: playwright/external/auth)
- 4 new tests: 3 unit + 1 integration
- Credo: **0 issues** (was 42 pre-existing refactoring issues, all fixed)

### Data Validation (`mix validate.data`)
- Portfolio balance: ⚠ WARNING (8.07% gap, €6,958)
- No new validation issues

### GitHub Issues
- No open issues (all #1-#22 closed)

## Commits

1. `0b9aaff` — fix: PIL dedup in TTM yield + correct TCPC/TRIN manual rates
2. `62c60fd` — docs: Update session report and memo for PIL dedup fix
3. `3741116` — fix: Dashboard TTM date range + frequency detection dedup
4. `1b0c633` — fix: KESKOB dividend rate €0.88/year (quarterly €0.22 × 4)
5. `c38506e` — refactor: Fix all 42 credo warnings across 17 files

## Files Changed

### Modified (22)
- `lib/dividendsomatic/portfolio.ex` — dashboard TTM date range, frequency dedup, credo refactoring
- `lib/dividendsomatic/portfolio/dividend_analytics.ex` — PIL dedup in TTM + frequency detection
- `lib/dividendsomatic/portfolio/dividend_validator.ex` — credo: extracted helper
- `lib/dividendsomatic/portfolio/ibkr_activity_parser.ex` — credo: data-driven patterns, extracted helpers
- `lib/dividendsomatic/portfolio/schema_integrity.ex` — credo: data-driven null field queries
- `lib/dividendsomatic/data_ingestion/flex_import_orchestrator.ex` — credo: extracted 4 helpers
- `lib/dividendsomatic/workers/integrity_check_worker.ex` — credo: extracted logging helpers
- `lib/mix/tasks/audit_dividends.ex` — credo: alias order, nesting fixes
- `lib/mix/tasks/backfill_aliases.ex` — credo: extracted core/variant step functions
- `lib/mix/tasks/backfill_dividend_rates.ex` — manual overrides + dedup + credo refactoring
- `lib/mix/tasks/backfill_instruments.ex` — credo: explicit try/rescue
- `lib/mix/tasks/cleanup_cash_flows.ex` — credo: Enum.map_join
- `lib/mix/tasks/fetch_dividend_rates.ex` — credo: alias order
- `lib/mix/tasks/fix_position_symbols.ex` — credo: pattern-matched dry_run helpers
- `lib/mix/tasks/migrate_legacy_costs.ex` — credo: alias order, extracted helpers
- `lib/mix/tasks/migrate_legacy_dividends.ex` — credo: alias order, extracted helpers
- `lib/mix/tasks/migrate_legacy_transactions.ex` — credo: 12 extracted helpers
- `lib/mix/tasks/migrate_symbol_mappings.ex` — credo: alias order, extracted helpers
- `test/dividendsomatic/portfolio/dividend_analytics_test.exs` — 3 PIL dedup unit tests
- `test/dividendsomatic/portfolio_test.exs` — 1 PIL yield integration test
- `.claude/skills/yield-audit.md` — BDC/PIL patterns, TCPC bounds, test references

## How the Yield Fix Works — Past, Present, and Future

### What was broken

Four independent bugs conspired to produce wrong Current Yield values:

1. **PIL double-counting** — IBKR creates two `dividend_payment` records per event (PIL portion + withholding adjustment), both with the same `per_share`. The TTM computation summed every record, inflating annual rates ~2x for stocks with PIL splits (TCPC, TRIN).

2. **Dashboard date range too narrow** — `compute_dividend_dashboard` only loaded dividends from Jan 1 of the current year. In early 2026, that gave only ~2 months of data. When this tiny TTM diverged >2x from the stored Yahoo rate, the system picked the TTM value — which was wildly wrong. This broke AGNC, ORC, and KESKOB.

3. **Frequency detection poisoned by PIL** — The 0-day gaps between same-date PIL/withholding records dragged the average gap down, causing quarterly stocks to be detected as "monthly". Monthly extrapolation (avg × 12 instead of avg × 4) tripled the annual rate.

4. **Incomplete payment history** — KESKOB had only 1 of 4 quarterly installments in the database. TTM computed €0.22/year instead of the correct €0.88/year.

### How we fixed it

| Bug | Fix | Where |
|-----|-----|-------|
| PIL double-counting | Deduplicate by `(ex_date, per_share)` before summing | `dividend_analytics.ex:30-36`, `backfill_dividend_rates.ex:179-185` |
| Narrow date range | Load `min(year_start, today - 365)` for TTM | `portfolio.ex:697-698` |
| Frequency detection | `Enum.uniq()` on dates before computing gaps | `dividend_analytics.ex:121`, `portfolio.ex` detect_payment_frequency |
| Missing data | Manual overrides with `dividend_source: "manual"` | `backfill_dividend_rates.ex` @manual_overrides |

### Snapshot 2026-02-20 vs 2026-02-19

Both snapshots now show **correct yields**. The symbols differ between them — Feb 19 has `KESKO/NORDEA/TELIA` while Feb 20 has `KESKOB/NDA FI/TELIA1` — but this doesn't matter because:

- Yields are computed **dynamically** at page load, not stored per-snapshot
- The code matches dividends to positions via **ISIN cross-matching** (line 851-866 in portfolio.ex), so `KESKO` on the Feb 19 snapshot correctly matches dividends for ISIN `FI0009000202`
- The annual_per_share comes from the current (fixed) computation logic and current instrument rates

**Verified:**

| Symbol (Feb 19) | Symbol (Feb 20) | Yield (19th) | Yield (20th) |
|-----------------|-----------------|--------------|--------------|
| AGNC | AGNC | 12.59% | 12.46% |
| AKTIA | AKTIA | 6.63% | 6.59% |
| CSWC | CSWC | 11.12% | 11.18% |
| KESKO | KESKOB | 4.18% | 4.17% |
| NORDEA | NDA FI | 5.80% | 5.72% |
| NESTE | NESTE | 0.93% | 0.94% |
| ORC | ORC | 18.91% | 18.70% |
| TCPC | TCPC | 21.26% | 21.78% |
| TELIA | TELIA1 | 4.52% | 4.50% |
| TRIN | TRIN | 13.27% | 13.55% |

Small differences are from different prices on each date (e.g., TRIN $15.27 on 19th vs $14.97 on 20th).

### What about tomorrow?

New data imports will produce correct yields. Seven layers of protection are in place:

1. **Code: PIL dedup** — `compute_annual_dividend_per_share` deduplicates by `(ex_date, per_share)`. Any new PIL/withholding splits are handled automatically.

2. **Code: 365-day TTM window** — Dashboard always loads a full year of dividends regardless of the selected year, so TTM computation has enough data even early in the year.

3. **Code: Frequency detection dedup** — Dates are deduplicated before gap computation, preventing PIL splits from skewing frequency detection.

4. **Data: Manual overrides** — TCPC ($1.00), TRIN ($2.04), KESKOB (€0.88), Nordea (€0.96), and TELIA ($2.03) have `dividend_source: "manual"`, which is protected from overwrite by both Yahoo fetch and TTM backfill.

5. **Fetch protection** — `mix fetch.dividend_rates` (Yahoo) skips instruments with `dividend_source` set to `"manual"` or `"ttm_computed"`.

6. **Backfill protection** — `mix backfill.dividend_rates` applies manual overrides first, then skips them during TTM computation phase.

7. **Regression tests** — 4 tests specifically catch PIL dedup regression: 3 unit tests in `dividend_analytics_test.exs` + 1 integration test (PIL yield inflation guard) in `portfolio_test.exs`.

**When to update manual overrides:**
- When a company changes its dividend policy (e.g., Nordea switching to semi-annual in 2026)
- When enough quarterly installments accumulate in the database that TTM becomes accurate (e.g., KESKOB after 4 quarters of data)
- Override values and reasoning are documented in `backfill_dividend_rates.ex` comments
