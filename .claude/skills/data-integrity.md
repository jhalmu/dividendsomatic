---
name: data-integrity
description: Use when data looks wrong, after imports, during EOD, or when investigating dividend/portfolio data quality issues. Covers validation, triage, and threshold tuning.
---

# Data Integrity Triage

## Quick Commands

```bash
mix validate.data              # Run all 6 checks
mix validate.data --suggest    # Suggest threshold adjustments
mix validate.data --export     # Export timestamped snapshot + latest
mix validate.data --compare    # Compare current vs latest snapshot
mix check.all                  # Validation + gap analysis in one pass
mix report.gaps                # Data gap analysis only
```

## The 6 Checks

### 1. Invalid Currencies (`invalid_currencies`)
- **Severity**: warning
- **What**: Currency code not in known list
- **Triage**: Check CSV source for typos. If legit, add to `@valid_currencies` in `dividend_validator.ex`

### 2. ISIN-Currency Mismatch (`isin_currency_mismatches`)
- **Severity**: info
- **What**: ISIN country prefix doesn't match dividend currency
- **Triage**: Check `@isin_currency_map`. Known exception: IE ISINs can pay USD (Irish-domiciled ETFs)
- **False positives**: IE ISINs paying USD is normal (e.g., CSPX, VUSA)

### 3. Suspicious Amounts (`suspicious_amounts`)
- **Severity**: warning
- **What**: Per-share amount exceeds ~$50 USD equivalent threshold for its currency
- **Triage**: Check if record is actually total_net misclassified as per_share. BDC special dividends (ARCC, MAIN, AGNC) can be legitimately high
- **False positives**: BDC special dividends, return-of-capital distributions

### 4. Inconsistent Amounts (`inconsistent_amounts_per_stock`)
- **Severity**: warning
- **What**: Per-share amounts for same ISIN vary >10x from median
- **Triage**: Usually a total_net amount mixed in as per_share. Check the outlier record's source CSV

### 5. Mixed Amount Types (`mixed_amount_types_per_stock`)
- **Severity**: info
- **What**: Same stock has both per_share and total_net records
- **Triage**: This is informational. The UI handles both types. Only investigate if amounts look wrong

### 6. Cross-Source Duplicates (`cross_source_duplicates`)
- **Severity**: warning
- **What**: Same ISIN+date appears in multiple records
- **Triage**: Different sources (ibkr vs yfinance) may both have the dividend. Keep the more detailed one (usually ibkr)

## Currency Threshold Reference

| Currency | Threshold | ~USD Equivalent |
|----------|-----------|-----------------|
| USD      | 50        | $50             |
| EUR      | 50        | $50             |
| CAD      | 70        | $50             |
| GBP      | 40        | $50             |
| GBp      | 4000      | $50 (pence)     |
| CHF      | 50        | $50             |
| AUD      | 80        | $50             |
| NZD      | 85        | $50             |
| SGD      | 70        | $50             |
| HKD      | 400       | $50             |
| JPY      | 7500      | $50             |
| NOK      | 550       | $50             |
| SEK      | 550       | $50             |
| DKK      | 350       | $50             |
| TWD      | 1600      | $50             |

## Discovering New Patterns

Use `mix validate.data --suggest` to see if any currency thresholds need adjustment based on actual data (uses 95th percentile * 1.2).

## Adding New Rules

1. Add check function in `lib/dividendsomatic/portfolio/dividend_validator.ex`
2. Wire it into `validate/0` issues list
3. Add tests in `test/dividendsomatic/portfolio/dividend_validator_test.exs`
4. Update this skill with the new check description

## Key Files

- `lib/dividendsomatic/portfolio/dividend_validator.ex` - All validation logic
- `lib/mix/tasks/validate_data.ex` - CLI task
- `lib/mix/tasks/check_all.ex` - Unified integrity check
- `test/dividendsomatic/portfolio/dividend_validator_test.exs` - Tests
