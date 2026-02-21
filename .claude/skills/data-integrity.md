---
name: data-integrity
description: Use when data looks wrong, after imports, during EOD, or when investigating dividend/portfolio data quality issues. Covers validation, triage, and threshold tuning.
---

# Data Integrity Triage

## Quick Commands

```bash
mix validate.data              # Run all 7 checks
mix validate.data --suggest    # Suggest threshold adjustments
mix validate.data --export     # Export timestamped snapshot + latest
mix validate.data --compare    # Compare current vs latest snapshot
mix check.all                  # Validation + gap analysis + schema integrity
mix report.gaps                # Data gap analysis only
```

## Legacy Table Status

All 6 legacy tables have been **dropped** (2026-02-21):
- `legacy_holdings` → migrated to `positions`
- `legacy_portfolio_snapshots` → migrated to `portfolio_snapshots`
- `legacy_symbol_mappings` → migrated to `instrument_aliases`
- `legacy_dividends` → broker records to `dividend_payments`, yfinance archived to JSON
- `legacy_broker_transactions` → `trades`, `dividend_payments`, `cash_flows`, `corporate_actions`
- `legacy_costs` → interest/fees to `cash_flows` (commissions already on trades, taxes on dividend_payments)

## Schema Integrity Checks (NEW)

`mix check.all` now includes 4 schema-level checks via `SchemaIntegrity`:

### 1. Orphan Check
- Instruments with no trades or dividend payments
- Positions with no parent snapshot
- Instrument aliases with no parent instrument

### 2. Null Field Check
- Dividend payments missing `amount_eur`
- Non-EUR dividend payments missing `fx_rate`
- Instruments missing `currency`
- Sold positions missing ISIN

### 3. FK Integrity Check
- Trades pointing to non-existent instruments
- Dividend payments pointing to non-existent instruments
- Corporate actions pointing to non-existent instruments

### 4. Duplicate Check
- Duplicate `external_id` in trades, dividend_payments, cash_flows
- Duplicate snapshot dates

## Oban Worker

`IntegrityCheckWorker` runs daily at 06:00 UTC via Oban cron. Runs the same SchemaIntegrity checks and logs warnings if issues are found.

## The 7 Dividend Validation Checks

### 1. Invalid Currencies (`invalid_currencies`)
- **Severity**: warning
- **What**: Currency code not in known list
- **Triage**: Check CSV source for typos. If legit, add to `@valid_currencies` in `dividend_validator.ex`

### 2. ISIN-Currency Mismatch (`isin_currency_mismatches`)
- **Severity**: info
- **What**: ISIN country prefix doesn't match dividend currency
- **Triage**: Check `@isin_currency_map`. Known exception: IE ISINs can pay USD (Irish-domiciled ETFs)

### 3. Suspicious Amounts (`suspicious_amounts`)
- **Severity**: warning
- **What**: Per-share amount exceeds ~$50 USD equivalent threshold for its currency
- **Triage**: Check if record is actually total_net misclassified as per_share

### 4. Inconsistent Amounts (`inconsistent_amounts_per_stock`)
- **Severity**: warning
- **What**: Per-share amounts for same ISIN vary >10x from median
- **Triage**: Usually a total_net amount mixed in as per_share

### 5. Mixed Amount Types (`mixed_amount_types_per_stock`)
- **Severity**: info
- **What**: Same stock has both per_share and total_net records

### 6. Cross-Source Duplicates (`cross_source_duplicates`)
- **Severity**: warning
- **What**: Same ISIN+date appears in multiple records

### 7. Missing FX Conversion (`missing_fx_conversion`)
- **Severity**: warning
- **What**: `total_net` dividend in non-EUR currency has nil or 1.0 `fx_rate`

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

## Adding New Rules

1. For dividend checks: add in `dividend_validator.ex`, wire into `validate/0`
2. For schema checks: add in `schema_integrity.ex`, wire into `check_all/0`
3. Add tests
4. Update this skill

## Key Files

- `lib/dividendsomatic/portfolio/dividend_validator.ex` - Dividend validation
- `lib/dividendsomatic/portfolio/schema_integrity.ex` - Schema integrity checks
- `lib/dividendsomatic/portfolio/data_gap_analyzer.ex` - Gap analysis
- `lib/dividendsomatic/workers/integrity_check_worker.ex` - Daily Oban worker
- `lib/mix/tasks/validate_data.ex` - CLI validation task
- `lib/mix/tasks/check_all.ex` - Unified integrity check
