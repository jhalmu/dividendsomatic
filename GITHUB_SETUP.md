# GitHub Setup Guide

## 1. Luo GitHub Repository

```bash
# Vaihtoehto A: gh CLI (jos asennettu)
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic
gh auth login  # Jos ei vielä kirjautunut
gh repo create dividendsomatic --public --source=. --remote=origin --push

# Vaihtoehto B: Manuaalinen
# 1. Mene https://github.com/new
# 2. Nimi: dividendsomatic
# 3. Julkinen (public)
# 4. Älä lisää README, .gitignore tai lisenssiä (meillä on jo)
# 5. Luo repo
# 6. Aja lokaalisti:
git remote add origin https://github.com/KÄYTTÄJÄNIMI/dividendsomatic.git
git branch -M main
git push -u origin main
```

## 2. Luo GitHub Issues

Kopioi ja liitä seuraavat issueiksi GitHubiin:

### Issue #1: ✅ DONE - MVP Portfolio Viewer

**Status:** ✅ Completed

**Description:**
Basic portfolio viewer with LiveView

**Completed:**
- [x] Database schema (portfolio_snapshots + holdings)
- [x] CSV parser with NimbleCSV
- [x] Mix task: `mix import.csv`
- [x] LiveView with DaisyUI table
- [x] Keyboard navigation (← →)
- [x] Summary cards (Total Holdings, Value, P&L)
- [x] Color-coded P&L display

**Files:**
- `lib/dividendsomatic/portfolio.ex`
- `lib/dividendsomatic/portfolio/portfolio_snapshot.ex`
- `lib/dividendsomatic/portfolio/holding.ex`
- `lib/dividendsomatic_web/live/portfolio_live.ex`
- `lib/mix/tasks/import_csv.ex`
- `priv/repo/migrations/20260129210334_create_portfolio_system.exs`

---

### Issue #2: 🚧 TODO - Automated Gmail CSV Import

**Status:** 🚧 In Progress

**Priority:** High

**Description:**
Automate daily CSV import from Gmail using MCP

**Tasks:**
- [ ] Configure Oban for SQLite
- [ ] Create GmailImportWorker
- [ ] Use Gmail MCP to fetch Activity Flex emails
- [ ] Extract CSV attachments
- [ ] Parse and import automatically
- [ ] Add cron schedule (daily at 8 AM)
- [ ] Error handling and notifications

**Dependencies:**
- Gmail MCP server
- Oban with SQLite notifier

**Notes:**
Current code exists but Oban is disabled due to SQLite compatibility.

---

### Issue #3: 📊 TODO - Portfolio Charts

**Status:** 📋 Planned

**Priority:** Medium

**Description:**
Add visual charts for portfolio analysis

**Tasks:**
- [ ] Add Contex library
- [ ] Portfolio value over time (line chart)
- [ ] Holdings allocation (pie chart)
- [ ] P&L trends (bar chart)
- [ ] Currency breakdown
- [ ] Export charts as images

**UI Location:**
New section below holdings table

---

### Issue #4: 💰 TODO - Dividend Tracking

**Status:** 📋 Planned

**Priority:** Medium

**Description:**
Track dividends and project future income

**Tasks:**
- [ ] Create dividends table schema
- [ ] Manual dividend entry form
- [ ] Link dividends to holdings
- [ ] Calculate total dividend income
- [ ] Project future dividends
- [ ] Dividend calendar view
- [ ] Export dividend reports

**New Models:**
- `Dividend` schema
- `DividendProjection` calculations

---

### Issue #5: 🔧 TODO - Deployment Setup

**Status:** 📋 Planned

**Priority:** Medium

**Description:**
Deploy to production (Hetzner/Fly.io)

**Tasks:**
- [ ] Switch to PostgreSQL for production
- [ ] Configure production environment
- [ ] Set up CI/CD
- [ ] Add health checks
- [ ] Configure backups
- [ ] SSL/TLS setup
- [ ] Monitoring and logging

**Decision Needed:**
- Hetzner Cloud vs Fly.io vs Railway

---

### Issue #6: ✨ TODO - UI/UX Improvements

**Status:** 📋 Planned

**Priority:** Low

**Description:**
Polish the user interface

**Tasks:**
- [ ] Add theme selector (DaisyUI themes)
- [ ] Responsive mobile layout
- [ ] Loading states and skeletons
- [ ] Better error messages
- [ ] Tooltips for columns
- [ ] Sorting and filtering
- [ ] Search holdings
- [ ] Export to CSV/Excel

---

### Issue #7: 🧪 TODO - Testing

**Status:** 📋 Planned

**Priority:** Medium

**Description:**
Add comprehensive test coverage

**Tasks:**
- [ ] Context tests for Portfolio
- [ ] LiveView tests
- [ ] CSV parser tests
- [ ] Factory setup with ExMachina
- [ ] Integration tests for CSV import
- [ ] Property-based tests for calculations

**Target Coverage:** 80%+

---

## 3. Projektin Status

**Mitä on TEHTY:**
- ✅ MVP portfolio viewer toimii
- ✅ CSV import manuaalisesti
- ✅ Tietokanta ja schemat
- ✅ LiveView näkymä
- ✅ Nuolinäppäimet

**Mitä on TEKEMÄTTÄ:**
- 🚧 Gmail automaatio (Oban + MCP)
- 📊 Grafiikat (Contex)
- 💰 Osinko-seuranta
- 🔧 Deployment
- ✨ UI polish
- 🧪 Testit

**Seuraava Prioriteetti:**
Issue #2 - Gmail automaatio (vaatii Oban + SQLite konffi)

## 4. Kehityskomennot

```bash
# Import CSV
mix import.csv flex.490027.PortfolioForWww.20260128.20260128.csv

# Käynnistä serveri
mix phx.server  # http://localhost:4000

# Tietokanta
mix ecto.reset
mix ecto.migrate

# Testit (tulevaisuudessa)
mix test

# Formatointi
mix format

# Credo (tulevaisuudessa)
mix credo
```

## 5. Tiedostorakenne

```
dividendsomatic/
├── lib/
│   ├── dividendsomatic/
│   │   ├── portfolio.ex              # Context
│   │   ├── portfolio/
│   │   │   ├── portfolio_snapshot.ex
│   │   │   └── holding.ex
│   │   ├── gmail.ex                  # TODO: MCP integration
│   │   └── workers/
│   │       └── gmail_import_worker.ex # TODO: Oban worker
│   ├── dividendsomatic_web/
│   │   └── live/
│   │       └── portfolio_live.ex     # ✅ MVP LiveView
│   └── mix/
│       └── tasks/
│           └── import_csv.ex         # ✅ Manual import
├── priv/
│   └── repo/
│       └── migrations/
│           └── 20260129210334_create_portfolio_system.exs
├── CLAUDE.md                         # Dev guide
├── SESSION_REPORT.md                 # Latest session
├── GITHUB_SETUP.md                   # This file
└── README.md                         # Project overview
```
