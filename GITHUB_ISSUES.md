# GitHub Issues - Dividendsomatic

## ✅ TEHTY (Completed)

### Milestone 1: MVP Basic Functionality
- [x] **Setup**: Phoenix 1.8.1 + LiveView 1.1.0 project
- [x] **Database**: SQLite schema with `portfolio_snapshots` and `holdings` tables
- [x] **CSV Parser**: NimbleCSV integration for Interactive Brokers CSV files
- [x] **Import Tool**: `mix import.csv` command for CSV import
- [x] **LiveView**: Portfolio viewer with DaisyUI components
- [x] **Navigation**: Arrow key navigation (← →) between dates
- [x] **Display**: Holdings table with P&L highlighting
- [x] **Design**: Design tokens from homesite for responsive spacing
- [x] **Git**: Initial repository setup with proper .gitignore

## 🚧 TODO (To Be Implemented)

### Priority 1: Core Features
- [ ] **Auto-import from Gmail**: Use Gmail MCP to fetch daily CSV files automatically
- [ ] **Oban Worker**: Schedule daily CSV imports
- [ ] **Date picker**: Calendar widget for quick date navigation
- [ ] **Search/Filter**: Filter holdings by symbol, currency, or asset class

### Priority 2: Charts & Analytics
- [ ] **Portfolio Value Chart**: Line chart showing portfolio value over time (Contex library)
- [ ] **Asset Allocation**: Pie chart showing breakdown by currency/asset class
- [ ] **P&L Timeline**: Chart showing cumulative profit/loss
- [ ] **Holdings History**: Track individual holding performance over time

### Priority 3: Dividend Tracking
- [ ] **Dividend Table**: Separate table for dividend payments
- [ ] **Dividend Calculator**: Project future dividends based on holdings
- [ ] **Dividend History**: Track received dividends over time
- [ ] **Yield Analysis**: Calculate portfolio yield and dividend growth

### Priority 4: Enhancements
- [ ] **Export**: Export portfolio to PDF/Excel
- [ ] **Alerts**: Email/notification for portfolio changes
- [ ] **Multi-currency**: Convert all values to single base currency
- [ ] **Cost Basis Tracking**: Better visualization of cost basis vs current value
- [ ] **Tax Reporting**: Generate tax reports for capital gains

### Priority 5: Production
- [ ] **PostgreSQL**: Switch from SQLite to PostgreSQL for production
- [ ] **Authentication**: Add user authentication (multi-user support)
- [ ] **Deployment**: Deploy to Fly.io or Railway
- [ ] **Monitoring**: Add error tracking and monitoring
- [ ] **Tests**: Add comprehensive test suite

## 📝 GitHub Issue Templates

### For Gmail Auto-Import:
```
**Title**: Implement Gmail MCP auto-import for daily CSV files

**Description**:
Use Gmail MCP connector to automatically fetch daily Activity Flex CSV files from Interactive Brokers emails.

**Tasks**:
- [ ] Install Gmail MCP connector
- [ ] Configure MCP to search for emails with subject "Activity Flex"
- [ ] Extract CSV attachments from emails
- [ ] Integrate with existing `Portfolio.create_snapshot_from_csv/2`
- [ ] Add Oban worker for daily schedule
- [ ] Add error handling and notifications

**Dependencies**: Gmail MCP, Oban

**Priority**: High
```

### For Charts Implementation:
```
**Title**: Add portfolio value chart with Contex

**Description**:
Create interactive charts showing portfolio performance over time using Contex library.

**Tasks**:
- [ ] Install Contex library
- [ ] Create chart LiveView component
- [ ] Query portfolio values across all snapshots
- [ ] Implement line chart for portfolio value
- [ ] Add date range selector
- [ ] Style with DaisyUI theme

**Dependencies**: Contex

**Priority**: Medium
```

### For Dividend Tracking:
```
**Title**: Implement dividend tracking and projections

**Description**:
Add comprehensive dividend tracking with historical data and future projections.

**Tasks**:
- [ ] Create `dividends` table migration
- [ ] Add Dividend schema and context
- [ ] Parse dividend data from CSV (if available)
- [ ] Create dividend input form (manual entry)
- [ ] Build dividend history view
- [ ] Implement yield calculator
- [ ] Add projected dividend calculator

**Priority**: Medium
```

## 📋 How to Create Issues on GitHub

Once repository is pushed to GitHub:

1. Go to: https://github.com/jhalmu/dividendsomatic/issues
2. Click "New Issue"
3. Use titles from "TODO" section above
4. Add labels: `enhancement`, `priority-high`, `priority-medium`, etc.
5. Assign to milestones as appropriate

## 🎯 Suggested Milestones

1. **MVP Launch** (Current) - Basic CSV import and viewing
2. **Automation** - Gmail integration + Oban scheduling
3. **Analytics** - Charts and visualizations
4. **Dividends** - Full dividend tracking
5. **Production** - Multi-user deployment

## 📊 Progress Tracking

**Completed**: 9 tasks
**In Progress**: 0 tasks
**Remaining**: 25+ tasks
**Progress**: ~25% of full vision complete
