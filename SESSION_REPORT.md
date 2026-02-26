# Session Report — 2026-02-26 (IBKR Declared Dividend Rates)

## Overview

Replaced complex TTM + frequency detection + PIL dedup + extrapolation chain with simple declared per-share rates from IBKR. New formula: `est_annual = per_payment × payments_per_year × quantity × fx_rate`. Five interconnected bug patterns eliminated.

## Changes Made

### Schema (Step 1)
- Migration adds `dividend_per_payment` (decimal) and `payments_per_year` (integer) to instruments table
- Instrument schema updated with new fields in `@optional_fields` and `schema` block

### CSV Parsers (Steps 2-3)
- **FlexCsvRouter** — detects `:portfolio_with_accruals` type (portfolio CSV with second GrossRate/ExDate header)
- **FlexPortfolioAccrualsParser** (new) — splits combined CSV, delegates positions to CsvParser, parses accruals to update instrument rates
- **IbkrActivityParser** — now processes "Change in Dividend Accruals" section, extracts GrossRate from "Po" (posted) rows, updates `instrument.dividend_per_payment`
- **FlexImportOrchestrator** — routes new `:portfolio_with_accruals` type

### Backfill Task (Step 4)
- All 10 IBKR reference instruments seeded with declared per-payment rates + payments_per_year
- ISINs corrected: CSWC (US1405011073), FSK (US3026352068), MANTA (FI4000552526), OBDC (US69121K1043)
- Source changed from "manual" to "declared"
- TTM path also populates new fields when frequency is deterministic

### Simplified Projection (Step 5)
- `build_symbol_dividend_data` checks for declared per-payment rates first
- Declared path: `per_payment × ppy` for annual, then `× qty × fx` for projection
- Falls back to existing TTM logic only when declared rates are missing
- Positions with declared rates but no dividend history are now included

### Validation (Step 6)
- Post-insert check on dividend payments: compares per_share against instrument's declared rate
- >10% divergence logs warning and auto-updates instrument rate (source: "payment_observed")

### UI Updates (Step 7)
- Added **Freq** column to income per-symbol table with badges: M/Q/S/A/IR
- Holdings tab shows frequency badge next to est. monthly for all payers
- `frequency_label/1` and `frequency_title/1` helpers in FormatHelpers

## IBKR Reference Rates Seeded

| Symbol | ISIN | $/€ per payment | Freq | Annual |
|--------|------|-----------------|------|--------|
| AGNC | US00123Q1040 | $0.12 | 12×/yr | $1.44 |
| CSWC | US1405011073 | $0.1934 | 12×/yr | $2.3208 |
| FSK | US3026352068 | $0.645 | 4×/yr | $2.58 |
| KESKOB | FI0009000202 | €0.22 | 4×/yr | €0.88 |
| MANTA | FI4000552526 | €0.33 | 1×/yr | €0.33 |
| NDA FI | FI4000297767 | €0.94 | 1×/yr | €0.94 |
| OBDC | US69121K1043 | $0.37 | 5×/yr | $1.85 |
| ORC | US68571X3017 | $0.12 | 12×/yr | $1.44 |
| TCPC | US09259E1082 | $0.25 | 4×/yr | $1.00 |
| TRIN | US8964423086 | $0.17 | 12×/yr | $2.04 |
| ABB | SE0000667925 | CHF0.5075 | 4×/yr | CHF2.03 |

## Data Validation

```
=== Portfolio Balance Check ===
  Net invested:   €173,452.62
  Expected value: €73,410.24
  Current value:  €86,168.86
  Difference:     €12,758.62 (14.81%)
  Status:         ⚠ WARNING (5-20% difference, margin account)
```

## Credo

2 refactoring suggestions (nesting depth in new parser modules) — non-blocking.

## Files Changed

| File | Change |
|------|--------|
| `priv/repo/migrations/20260226131454_add_declared_dividend_fields.exs` | New migration |
| `lib/dividendsomatic/portfolio/instrument.ex` | +2 fields |
| `lib/dividendsomatic/portfolio/flex_csv_router.ex` | `:portfolio_with_accruals` detection |
| `lib/dividendsomatic/portfolio/flex_portfolio_accruals_parser.ex` | **New** |
| `lib/dividendsomatic/data_ingestion/flex_import_orchestrator.ex` | Route new type |
| `lib/dividendsomatic/portfolio/ibkr_activity_parser.ex` | Accruals parsing + validation |
| `lib/dividendsomatic/portfolio.ex` | Declared-rate projection path |
| `lib/mix/tasks/backfill_dividend_rates.ex` | IBKR reference rates |
| `lib/dividendsomatic_web/helpers/format_helpers.ex` | Frequency helpers |
| `lib/dividendsomatic_web/live/portfolio_live.html.heex` | Freq column + badges |

## Test Results

696 tests, 0 failures (27 excluded)
