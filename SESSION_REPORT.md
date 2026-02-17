# Session Report — 2026-02-17

## Fix Missing IBKR Dividends & Data Recovery Pipeline

### Context
426 of 650 IBKR dividend transactions were not making it into the `dividends` table. Root cause: the `DividendProcessor` regex failed on "Payment in Lieu of Dividend" (PIL) records (no per-share amount in description) and Foreign Tax entries misclassified as dividends. Additionally, valuable data sat unprocessed in `csv_data/` subfolders (81 Yahoo JSON files, 6 Flex dividend CSVs).

### Changes Made

#### Core Fix: DividendProcessor (Step 2)
- **PIL fallback chain**: Regex extraction → total_net fallback using `txn.amount`
- **Foreign Tax filter**: Skip records containing "Foreign Tax" without "Cash Dividend"
- **ISIN→currency map**: 15 country codes (US→USD, CA→CAD, SE→SEK, FI→EUR, etc.)
- **amount_type field**: New column distinguishes `per_share` vs `total_net` dividends
- **Income computation**: `total_net` returns amount directly (no qty*fx multiplication)

#### Schema Migration (Step 1)
- Added `amount_type` (string, default "per_share") to `dividends` table

#### Data Parsers (Step 3)
- `IbkrFlexDividendParser` — parses Flex dividend CSVs (Symbol, PayDate, NetAmount, FXRate, ISIN)
- `YahooDividendParser` — parses Yahoo Finance JSON files (symbol, isin, ex_date, amount, currency)

#### Import Tasks (Step 4)
- `mix import.flex_dividends` — imports Flex dividend CSV reports as total_net
- `mix import.yahoo_dividends` — imports Yahoo dividend JSONs from archive
- `mix process.data` — orchestrator: `--scan` | `--all` | `--archive`

#### Analysis & Validation (Steps 6-7)
- `DataGapAnalyzer` — 364-day chunk analysis, dividend gaps, snapshot gaps
- `DividendValidator` — currency codes, ISIN-currency matches, suspicious amounts, duplicates
- `mix report.gaps` — formatted gap report with `--format=markdown`, `--year=`, `--export`
- `mix validate.data` — validation report with `--export`

#### Data Recovery (Steps 8-9)
- `mix check.sqlite` — SQLite DB check (12 test dividends, no unique historical data)
- `scripts/extract_lynx_pdfs.py` — Python pdfplumber extraction (101 16B summaries, 3 cost records; dividend PDFs non-tabular)
- `mix import.lynx_data` — imports Lynx PDF-extracted JSON

### Pipeline Results (`mix process.data --all`)

| Step | Result |
|------|--------|
| Yahoo dividends | 0 new (5,709 already existed) |
| DividendProcessor | **51 new** (PIL total_net fallback) |
| Flex dividend CSVs | **22 new** from 6 files |
| Archive flex snapshots | 0 new (160 already imported) |
| **Total dividends** | **6,221** (up from 6,148, +73) |

### Diagnostics (`diagnose_dividends()`)

| Metric | Before | After |
|--------|--------|-------|
| Total dividends | 6,148 | 6,221 |
| Grand total | ~124K EUR | **137,299 EUR** |
| ISIN duplicates | 0 | 0 |

**Yearly breakdown**: 2026 YTD 8,707 | 2025 58,616 | 2024 19,096 | 2023 18,118 | 2022 22,401 | 2021 7,339 | 2020 77 | 2019 39 | 2018 2,030 | 2017 876

### Validation Report
- 6,221 dividends checked, **11 info-level issues** (ISIN-currency mismatches: 9x CIBUS SE→EUR, 1x BHP AU→GBP — both correct for their listings)
- No critical issues, no suspicious amounts, no duplicates

### Gap Report (364-day chunks)
- Best coverage: 2025-2026 at 75.2% (185/246 snapshots)
- Lowest coverage: 2019-2020 at 21.5% (54/251 snapshots)
- 41 stocks with dividend gaps >400 days (expected — position lifecycle gaps)

### Files Changed

| Category | Files |
|----------|-------|
| Modified (4) | `portfolio.ex`, `dividend.ex`, `dividend_processor.ex`, `.gitignore` |
| New modules (4) | `data_gap_analyzer.ex`, `dividend_validator.ex`, `ibkr_flex_dividend_parser.ex`, `yahoo_dividend_parser.ex` |
| New mix tasks (7) | `import_flex_dividends.ex`, `import_yahoo_dividends.ex`, `process_data.ex`, `report_gaps.ex`, `validate_data.ex`, `check_sqlite.ex`, `import_lynx_data.ex` |
| New scripts (1) | `scripts/extract_lynx_pdfs.py` |
| Migration (1) | `add_amount_type_to_dividends.exs` |
| Tests (4) | `dividend_processor_test.exs` (expanded), `data_gap_analyzer_test.exs`, `dividend_validator_test.exs`, `ibkr_flex_dividend_parser_test.exs`, `yahoo_dividend_parser_test.exs` |

**22 files changed, +2,374 lines**

### Quality
- 500 tests, 0 failures (up from 447)
- 0 credo issues (--strict)
- Code formatted

### Exported Data
```
data_revisited/
  gap_report.json          16KB — full 364-day chunk analysis
  validation_report.json   2.5KB — currency/amount/duplicate checks
  sqlite_unique.json       2.8KB — SQLite dev DB dump (test data only)
  lynx/
    16b_summaries.json     101 annual tax summary lines
    costs.json             3 cost records (2023-2024)
```
