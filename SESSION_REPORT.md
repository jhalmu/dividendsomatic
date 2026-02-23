# Session Report — 2026-02-23 (Yield FX Mismatch Regression Tests & Audit Skill)

## Overview

Added regression tests for the yield FX mismatch bug (div_fx defaulting to 1.0 instead of pos.fx_rate, inflating USD yields by ~17%) and created a weekly yield-audit Claude skill for ongoing verification.

## Post-Mortem: Yield FX Bug

### Root Cause
The `div_fx` fallback in yield/projected_annual calculations used `1.0` when `div_fx_rate` was nil, instead of falling back to `pos.fx_rate`. For same-currency positions (e.g., USD dividend on USD stock), this meant:
- `div_fx = 1.0` but `pos_fx = 0.85` (the EUR conversion rate)
- Yield formula: `(annual × 1.0) / (price × 0.85)` — numerator NOT EUR-converted, denominator IS
- Result: yields inflated by `1 / pos_fx` factor (~17% for USD at fx_rate 0.85)

### Impact
- All USD stock yields were ~17% too high
- Cross-currency stocks (SEK dividends on EUR positions) were affected differently
- `projected_annual` used the CORRECT fallback (pos.fx_rate), creating an inconsistency between yield and projected values

### Fix (applied in prior session)
Changed fallback chain to: `div_fx = div_fx_rate || pos.fx_rate || 1.0`
This ensures same-currency positions cancel FX correctly: `(annual × 0.85) / (price × 0.85) = annual / price`

### Prevention (this session)
- 3 regression tests catch the exact bug pattern
- Weekly yield-audit skill documents invariants and reference values

## Changes

### 1. Regression Tests (`test/dividendsomatic/portfolio_test.exs`)
Added `describe "yield FX consistency"` with 3 tests:

1. **Same-currency yield (USD/USD)** — nil div_fx_rate must not inflate yield
   - Asserts current_yield = 13.33% and yield_on_cost = 16.67%
   - Before fix: would give ~15.7% / ~19.6%

2. **Cross-currency yield (SEK/EUR)** — explicit div_fx_rate used correctly
   - Asserts current_yield = 4.29% and yield_on_cost = 4.74%
   - Uses div_fx_rate = 0.09 (SEK→EUR)

3. **Consistency invariant** — projected_annual and current_yield use same FX logic
   - Asserts `projected_annual / (price × qty × pos_fx) ≈ current_yield / 100`
   - This was the original mismatch root cause

### 2. Yield Audit Skill (`.claude/skills/yield-audit.md`)
Weekly audit checklist covering:
- Test execution and validation
- Spot-check procedures for USD, EUR, and cross-currency stocks
- Reference values (TELIA ~4.57%, TRIN ~13.63%, AKTIA ~6.59%, TCPC ~21.69%)
- Red flags table for diagnosing FX mismatch symptoms
- Formula reference with key invariant

### 3. CLAUDE.md EOD Workflow Update
Added step 3: "Weekly: invoke `yield-audit` skill" to the EOD checklist

## Verification

### Test Suite
- **682 tests, 0 failures** (25 excluded: playwright/external/auth)
- 3 new tests in "yield FX consistency" describe block
- Credo: 35 pre-existing refactoring issues — none from this session

### Data Validation (`mix validate.data`)
- Total checked: 2178, Issues found: 679
  - duplicate: 282 (warning), isin_currency_mismatch: 240 (info)
  - inconsistent_amount: 154 (info), suspicious_amount: 1 (warning)
  - mixed_amount_types: 2 (info)
- Portfolio balance: ⚠ WARNING (8.07% gap, €6,958)

### GitHub Issues
- No open issues (all #1-#22 closed)

## Files Changed

### Modified (2)
- `test/dividendsomatic/portfolio_test.exs` — 3 yield FX regression tests
- `CLAUDE.md` — weekly yield audit added to EOD workflow

### Created (1)
- `.claude/skills/yield-audit.md` — weekly yield audit skill
