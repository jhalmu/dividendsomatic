# GitHub Issues - Dividendsomatic

Käytä näitä kun luot GitHub repon:

## ✅ COMPLETED

### #1 - Project Setup ✓
**Status:** DONE
**Completion:** 2026-01-29

- [x] Phoenix 1.8.1 + LiveView 1.1.0 projekti
- [x] SQLite tietokanta (dev)
- [x] DaisyUI + Tailwind v4
- [x] NimbleCSV dependency

### #2 - Database Schema ✓
**Status:** DONE
**Completion:** 2026-01-29

- [x] portfolio_snapshots taulu (report_date unique)
- [x] holdings taulu (KAIKKI 18 CSV-kenttää)
- [x] Foreign key constraints
- [x] Proper indexes

### #3 - Portfolio Context ✓
**Status:** DONE
**Completion:** 2026-01-29

- [x] `get_latest_snapshot/0`
- [x] `get_snapshot_by_date/1`
- [x] `get_previous_snapshot/1`
- [x] `get_next_snapshot/1`
- [x] `create_snapshot_from_csv/2`

### #4 - CSV Import ✓
**Status:** DONE
**Completion:** 2026-01-29

- [x] NimbleCSV parser
- [x] Mix task `mix import.csv`
- [x] Parse all 18 fields
- [x] Transaction safety

### #5 - LiveView Portfolio Viewer ✓
**Status:** DONE
**Completion:** 2026-01-29

- [x] LiveView module
- [x] DaisyUI components (table, cards, buttons)
- [x] Summary stats (holdings count, total value, P&L)
- [x] Navigation buttons (← →)
- [x] Keyboard navigation (arrow keys)
- [x] Design tokens from homesite
- [x] Empty state message

---

## 🚧 IN PROGRESS

_None currently_

---

## 📋 TODO

### #6 - Gmail Integration
**Priority:** HIGH
**Estimated:** 3-4 hours

- [ ] Gmail MCP server integration
- [ ] Search for "Activity Flex" emails
- [ ] Download CSV attachments
- [ ] Parse filename for date
- [ ] Auto-import to database
- [ ] Error handling (duplicate dates, missing files)

**Tasks:**
1. Test Gmail MCP connection
2. Implement attachment download
3. Create import function
4. Add error logging

### #7 - Oban Background Jobs
**Priority:** HIGH
**Estimated:** 2 hours

- [ ] Add Oban dependency
- [ ] Create worker for Gmail import
- [ ] Daily cron schedule
- [ ] Retry logic
- [ ] Success/failure notifications

**Cron:**
```elixir
# Run at 8 AM daily
{Cron, expression: "0 8 * * *", worker: GmailImportWorker}
```

### #8 - Charts & Visualizations
**Priority:** MEDIUM
**Estimated:** 4-5 hours

- [ ] Add Contex dependency
- [ ] Portfolio value over time (line chart)
- [ ] Holdings distribution (pie chart)
- [ ] P&L by symbol (bar chart)
- [ ] Performance metrics

**Charts:**
1. Total portfolio value timeline
2. Asset allocation by symbol
3. Currency distribution
4. Profit/Loss trends

### #9 - Dividend Tracking
**Priority:** MEDIUM
**Estimated:** 3-4 hours

- [ ] Create dividends table
- [ ] Import dividend data
- [ ] Calculate yearly projections
- [ ] Display dividend calendar
- [ ] Show yield percentages

**Fields:**
- symbol
- payment_date
- ex_dividend_date
- amount
- currency
- type (qualified/ordinary)

### #10 - Enhanced UI Features
**Priority:** LOW
**Estimated:** 2-3 hours

- [ ] Filtering by symbol
- [ ] Sorting by columns
- [ ] Search functionality
- [ ] Date range selector
- [ ] Export to CSV
- [ ] Print-friendly view

### #11 - Authentication
**Priority:** LOW (Future)
**Estimated:** 3 hours

- [ ] User accounts (if needed)
- [ ] Session management
- [ ] Protected routes
- [ ] Multi-user support

### #12 - Testing
**Priority:** MEDIUM
**Estimated:** 4 hours

- [ ] Portfolio context tests
- [ ] LiveView tests
- [ ] CSV parsing tests
- [ ] Integration tests
- [ ] CI/CD setup

### #13 - Production Deployment
**Priority:** HIGH (when ready)
**Estimated:** 2-3 hours

- [ ] PostgreSQL setup (replace SQLite)
- [ ] Environment configuration
- [ ] Database migrations
- [ ] SSL certificates
- [ ] Error monitoring (Sentry?)

**Hosting options:**
- Fly.io
- Render.com
- Gigalixir
- Self-hosted (Hetzner?)

### #14 - Documentation
**Priority:** MEDIUM
**Estimated:** 1-2 hours

- [ ] API documentation
- [ ] Deployment guide
- [ ] User manual
- [ ] CSV format specification
- [ ] Troubleshooting guide

---

## 🐛 BUGS

_None reported yet_

---

## 💡 NICE TO HAVE

- Portfolio comparison (month-over-month)
- Tax reporting helpers
- Mobile app (LiveView Native?)
- Email notifications for big changes
- Performance benchmarks
- Dark mode theme
- Multiple portfolios support
- Notes on holdings
- Transaction history
- Alerts on price changes
