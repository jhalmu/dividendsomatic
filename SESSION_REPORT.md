# Session Report — 2026-02-23 (PIL Dedup + TCPC/TRIN Yield Fix)

## Overview

Fixed TCPC and TRIN showing wrong Current Yield values. Root cause: IBKR creates two dividend_payment records per event (PIL portion + withholding adjustment), both with the same per_share. Without deduplication, TTM computation summed each record separately, inflating the annual rate ~2×.

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

## Changes

### 1. PIL Dedup in TTM Computation (`dividend_analytics.ex`)
- Deduplicate by `(ex_date, per_share)` using `Enum.uniq_by` before summing
- Use unique **dates** (not record count) for `payment_count` in extrapolation
- Same fix applied in `backfill_dividend_rates.ex:compute_rate_from_payments`

### 2. Manual Override Corrections (`backfill_dividend_rates.ex`)
- TRIN: $4.08 → $2.04 (base monthly, excludes quarterly supplementals)
- TCPC: added $1.00 quarterly (new override)
- Both set as `dividend_source: "manual"` → protected from Yahoo/TTM overwrite

### 3. Instrument Data Fix (runtime)
- TCPC: rate $2.37→$1.00, frequency "monthly"→"quarterly", source→"manual"
- TRIN: rate $4.08→$2.04, source→"manual"

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

## Protection Chain (Future-Proofing)

| Layer | Protection |
|-------|-----------|
| `dividend_analytics.ex` | PIL dedup in TTM computation |
| `backfill_dividend_rates.ex` | PIL dedup in historical rate computation |
| `backfill_dividend_rates.ex` | Manual overrides with correct TCPC/TRIN values |
| `dividend_source: "manual"` | Protected from Yahoo fetch + TTM overwrite |
| `fetch_dividend_rates.ex` | Skips instruments with "manual"/"ttm_computed" source |
| Regression tests | 4 tests catch dedup regression |
| yield-audit skill | Documents patterns for future sessions |

## Verification

### Test Suite
- **686 tests, 0 failures** (25 excluded: playwright/external/auth)
- 4 new tests: 3 unit + 1 integration
- Credo: 35 pre-existing refactoring issues — none from this session

### Data Validation (`mix validate.data`)
- Portfolio balance: ⚠ WARNING (8.07% gap, €6,958)
- No new validation issues

### GitHub Issues
- No open issues (all #1-#22 closed)

## Files Changed

### Modified (5)
- `lib/dividendsomatic/portfolio/dividend_analytics.ex` — PIL dedup in TTM computation
- `lib/mix/tasks/backfill_dividend_rates.ex` — manual overrides + dedup fix
- `test/dividendsomatic/portfolio/dividend_analytics_test.exs` — 3 PIL dedup unit tests
- `test/dividendsomatic/portfolio_test.exs` — 1 PIL yield integration test
- `.claude/skills/yield-audit.md` — BDC/PIL patterns, TCPC bounds, test references
