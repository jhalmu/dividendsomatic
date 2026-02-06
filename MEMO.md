# MEMO.md

Session notes and progress tracking for the Dividendsomatic project.

---

## EOD Workflow

When user says **"EOD"**: Execute immediately without confirmation:
1. Run `mix test.all`
2. Sync GitHub issues (`gh issue list/close/comment`)
3. Update this MEMO.md with session summary
4. Commit & push
5. Check that CI/CD pipeline is green -> if not, investigate and fix issues

---

## Quick Commands

```bash
# Development
mix phx.server              # Start server (localhost:4000)
mix import.csv path/to.csv  # Import CSV data

# Testing
mix test.all                # Full test suite + credo
mix precommit               # compile + format + test

# Database
mix ecto.reset              # Drop + create + migrate
```

---

## Current Status

**Version:** 0.2.0 (Feature Complete)
**Status:** All planned features implemented, needs testing and production deployment

**Implemented:**
- CSV import from Interactive Brokers (`mix import.csv`)
- LiveView portfolio viewer with arrow-key navigation
- DaisyUI components + fluid design tokens
- Gmail integration (auto-fetch CSV attachments)
- Oban background worker (Gmail import scheduling)
- Contex charts (portfolio value over time)
- Dividend tracking
- Sold positions tracking
- Stock quotes & company profiles (Finnhub API)
- Market sentiment data
- What-if analysis

**Next priorities:**
- Testing coverage to 80% (#5, #8-#11)
- Production deployment (#6 - reopened)
- Enable Oban (needs SQLite notifier or PostgreSQL)

---

## 2026-01-30 (evening) - GitHub Issues & Cleanup

### Session Summary

Created GitHub issues for project roadmap, fixed compiler warnings, updated README.

### Changes Made

**GitHub Issues Created:**
- #1 Gmail MCP Integration
- #2 Oban Background Jobs
- #3 Charts & Visualizations
- #4 Dividend Tracking
- #5 Testing Suite
- #6 Production Deployment
- #7 Fix Compiler Warnings (closed)

**Compiler Warnings Fixed (#7):**
- Unused variable `max_results` -> `_max_results`
- Unused function `extract_report_date` -> `_extract_report_date`
- Removed unreachable error clause
- Commented out unused alias

**README Updated:**
- Fixed documentation links
- Added GitHub issue links to roadmap
- Updated last modified date

### Commits
- `9da7ce3` - fix: Fix compiler warnings and update README

---

## 2026-01-30 - Dependencies Update & Cleanup

### Session Summary

Updated project dependencies to match homesite, added dev/test quality tools, cleaned documentation.

### Changes Made

**Dependencies Added:**
- `credo` - static analysis
- `dialyxir` - type checking
- `sobelow` - security analysis
- `mix_audit` - dependency vulnerabilities
- `tailwind_formatter` - class sorting
- `phoenix_test` - better test helpers
- `phoenix_test_playwright` - browser testing
- `a11y_audit` - accessibility
- `timex` - date/time utilities
- `igniter` - code generation
- `tidewave` - dev tools

**Dependencies Updated:**
- `tailwind` 0.3 -> 0.4.1
- `phoenix_live_dashboard` -> 0.8.7
- `telemetry_metrics` -> 1.1.0
- `telemetry_poller` -> 1.3.0

**Documentation Cleanup:**
- Deleted 10 redundant MD files
- Created MEMO.md (Homesite pattern)
- Updated CLAUDE.md with EOD workflow

**New Aliases:**
- `mix test.all` - precommit + credo
- `mix test.full` - full test suite

### Files Modified
- `mix.exs` - Updated deps, added dialyzer config
- `CLAUDE.md` - Added EOD workflow, updated commands
- `MEMO.md` - Created (this file)

### Test Results
- 14 tests, 0 failures
- Credo: 6 readability issues, 12 design suggestions

---

## 2026-01-29 - MVP Complete

### Session Summary

Built complete MVP: CSV import, LiveView viewer, navigation, DaisyUI styling.

### Features Implemented

**Backend:**
- Portfolio context (CRUD + navigation)
- CSV parser with NimbleCSV
- Mix task: `mix import.csv`
- SQLite database (18 fields)

**Frontend:**
- LiveView portfolio viewer
- DaisyUI components (table, cards, stats)
- Arrow key navigation
- Design tokens from homesite
- Responsive layout
- Empty state

### Test Results
```bash
mix import.csv flex.490027.PortfolioForWww.20260128.20260128.csv
# 7 holdings imported successfully
```

### Commits
- Initial commit: Portfolio viewer with LiveView
- docs: Complete documentation

---

## GitHub Issues

| # | Title | Priority | Status |
|---|-------|----------|--------|
| [#1](https://github.com/jhalmu/dividendsomatic/issues/1) | Gmail MCP Integration | HIGH | **Closed** |
| [#2](https://github.com/jhalmu/dividendsomatic/issues/2) | Oban Background Jobs | HIGH | **Closed** |
| [#3](https://github.com/jhalmu/dividendsomatic/issues/3) | Charts & Visualizations | MEDIUM | **Closed** |
| [#4](https://github.com/jhalmu/dividendsomatic/issues/4) | Dividend Tracking | MEDIUM | **Closed** |
| [#5](https://github.com/jhalmu/dividendsomatic/issues/5) | Testing Suite | MEDIUM | Open |
| [#6](https://github.com/jhalmu/dividendsomatic/issues/6) | Production Deployment | HIGH | **Closed** |
| [#7](https://github.com/jhalmu/dividendsomatic/issues/7) | Fix Compiler Warnings | LOW | **Closed** |
| [#8](https://github.com/jhalmu/dividendsomatic/issues/8) | Add LiveView tests for PortfolioLive | MEDIUM | Open |
| [#9](https://github.com/jhalmu/dividendsomatic/issues/9) | Add accessibility tests with a11y_audit | MEDIUM | Open |
| [#10](https://github.com/jhalmu/dividendsomatic/issues/10) | Add Mix task tests for import.csv | MEDIUM | Open |
| [#11](https://github.com/jhalmu/dividendsomatic/issues/11) | Increase overall test coverage to 80% | MEDIUM | Open |

## Technical Debt

- [ ] Oban disabled (needs SQLite notifier or switch to PostgreSQL)
- [ ] Gmail integration needs OAuth env vars (`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`)
- [ ] Finnhub integration needs API key (`FINNHUB_API_KEY`)
- [ ] No production deployment (Fly.io or similar)
- [ ] Test coverage target: 80% (see #5, #8-#11)

## Credo Issues (mix credo --strict)

**Code Readability (6):**
- [ ] Missing `@moduledoc` - `lib/dividendsomatic/portfolio/portfolio_snapshot.ex`
- [ ] Missing `@moduledoc` - `lib/dividendsomatic/portfolio/holding.ex`
- [ ] Alias ordering - `lib/dividendsomatic_web.ex:91`
- [ ] Alias ordering - `lib/dividendsomatic/portfolio.ex:7-8`
- [ ] Trailing whitespace - `lib/dividendsomatic/gmail.ex:41`

**Software Design (14):**
- 11 TODO comments in Gmail/Worker files (expected - Issue #1 placeholders)
- 3 nested module alias suggestions (core_components.ex, data_case.ex)

---
