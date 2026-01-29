# TODO - Dividendsomatic

## ✅ Completed

- [x] Phoenix 1.8.1 + LiveView 1.1.0 setup
- [x] Database schema (portfolio_snapshots + holdings)
- [x] All 18 CSV fields stored
- [x] NimbleCSV parser
- [x] Mix task for CSV import (`mix import.csv`)
- [x] Portfolio context with navigation functions
- [x] LiveView viewer with DaisyUI
- [x] Arrow key navigation (← →)
- [x] Currency-grouped summary cards
- [x] P&L color coding
- [x] Responsive layout
- [x] Empty state
- [x] Git repo + GitHub

## 🚧 High Priority (MVP+)

- [ ] **Automated Gmail CSV import**
  - Gmail MCP integration
  - Oban worker for daily schedule
  - Search for "Activity Flex" emails
  - Download and import attachments
  - Error handling

- [ ] **Charts (Contex)**
  - Portfolio value over time
  - Per-currency breakdown
  - Individual holding performance
  - Date range selection

- [ ] **Dividend tracking**
  - Dividends table
  - Import dividend history
  - Projected annual dividends
  - Dividend yield calculations
  - Payment schedule

## 📋 Medium Priority

- [ ] **Testing suite**
  - Context tests
  - LiveView tests
  - CSV import tests
  - Navigation tests
  - Target: >80% coverage

- [ ] **Performance optimization**
  - Query optimization
  - Proper preloading
  - Database indexes
  - Caching summaries

- [ ] **Error handling**
  - CSV import errors
  - Data validation
  - User feedback
  - Error logging

## 🚀 Deployment

- [ ] PostgreSQL setup (replace SQLite)
- [ ] Hetzner Cloud configuration
- [ ] Docker + Caddy
- [ ] Environment variables
- [ ] GitHub Actions CI/CD
- [ ] Migration strategy

## 💡 Nice to Have

- [ ] Multiple portfolios/accounts
- [ ] Export to CSV/Excel
- [ ] Custom reports
- [ ] Email notifications
- [ ] Mobile app
- [ ] Tax reporting helper
- [ ] Benchmarking vs indexes

## 📝 Documentation

- [x] README.md
- [x] CLAUDE.md
- [x] SESSION_REPORT.md
- [x] GITHUB_ISSUES.md
- [ ] API documentation
- [ ] Deployment guide
- [ ] Contributing guide

## 🐛 Known Issues

None yet!

## 📊 Current Status

**Lines of Code:** ~1500
**Test Coverage:** 0%
**Features:** 40% MVP complete
**Ready for:** Local development ✅
**Ready for:** Production ❌
