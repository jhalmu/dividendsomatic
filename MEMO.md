# MEMO.md

Session notes and progress tracking for the Dividendsomatic project.

---

## EOD Workflow

When user says **"EOD"**: Execute immediately without confirmation:
1. Run `mix test.all`
2. Sync GitHub issues (`gh issue list/close/comment`)
3. Update this MEMO.md with session summary
4. Commit & push

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

**Version:** 0.1.0 (MVP)
**Status:** Fully functional

**Done:**
- CSV import from Interactive Brokers
- LiveView portfolio viewer
- Navigation (arrow keys)
- DaisyUI components
- Design tokens

**Next:**
- Gmail MCP integration (auto-fetch CSV)
- Oban worker (daily scheduling)
- Contex charts (portfolio value over time)
- Dividend tracking

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
| [#1](https://github.com/jhalmu/dividendsomatic/issues/1) | Gmail MCP Integration | HIGH | Open |
| [#2](https://github.com/jhalmu/dividendsomatic/issues/2) | Oban Background Jobs | HIGH | Open |
| [#3](https://github.com/jhalmu/dividendsomatic/issues/3) | Charts & Visualizations | MEDIUM | Open |
| [#4](https://github.com/jhalmu/dividendsomatic/issues/4) | Dividend Tracking | MEDIUM | Open |
| [#5](https://github.com/jhalmu/dividendsomatic/issues/5) | Testing Suite | MEDIUM | Open |
| [#6](https://github.com/jhalmu/dividendsomatic/issues/6) | Production Deployment | HIGH | Open |
| [#7](https://github.com/jhalmu/dividendsomatic/issues/7) | Fix Compiler Warnings | LOW | **Closed** |

## Technical Debt

- [ ] Oban disabled (needs SQLite notifier config)
- [ ] Gmail/Worker files exist but not active (stub code)
- [ ] Design tokens only partially used
- [ ] Missing @moduledoc on schemas

---
