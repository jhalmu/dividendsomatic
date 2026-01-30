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
- Compilation: Pending (server running)

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

## Technical Debt

- [ ] Tests not written yet
- [ ] Oban disabled (needs SQLite notifier config)
- [ ] Gmail/Worker files exist but not active
- [ ] Design tokens only partially used

## GitHub Issues (TODO)

Create these on GitHub:
- #6 - Gmail Integration (HIGH)
- #7 - Oban Background Jobs (HIGH)
- #8 - Charts & Visualizations (MEDIUM)
- #9 - Dividend Tracking (MEDIUM)
- #10 - Testing Suite (MEDIUM)
- #11 - Production Deployment (HIGH)

---
