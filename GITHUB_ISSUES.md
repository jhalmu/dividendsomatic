# GitHub Issues for Dividendsomatic

## Setup (käytä näitä gh CLI:llä)

```bash
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic

# Completed features
gh issue create --title "✅ Setup Phoenix project with LiveView" \
  --body "- Phoenix 1.8.1 + LiveView 1.1.0
- SQLite database (dev)
- DaisyUI + Tailwind CSS v4
- Project structure" \
  --label "completed"

gh issue create --title "✅ Database schema with all CSV fields" \
  --body "Tables:
- portfolio_snapshots (report_date, raw_csv_data)
- holdings (18 CSV fields: Symbol, Quantity, MarkPrice, etc.)

Indexes on: portfolio_snapshot_id, symbol, report_date" \
  --label "completed"

gh issue create --title "✅ CSV import with NimbleCSV" \
  --body "Mix task: \`mix import.csv path/to/file.csv\`

Features:
- NimbleCSV parser
- Transaction-based insert
- All 18 Interactive Brokers CSV fields
- Tested successfully with sample data" \
  --label "completed"

gh issue create --title "✅ LiveView portfolio viewer" \
  --body "Features:
- Latest snapshot display
- Holdings table with all key fields
- Currency-grouped summary cards
- Arrow key navigation (← →)
- P&L color coding (red/green)
- DaisyUI components
- Responsive layout
- Empty state with instructions" \
  --label "completed"

# TODO features
gh issue create --title "Automated CSV import from Gmail" \
  --body "Requirements:
- Gmail MCP integration
- Search for 'Activity Flex' emails from Interactive Brokers
- Download CSV attachments
- Oban worker for daily schedule
- Error handling and notifications

Files to create:
- lib/dividendsomatic/workers/gmail_import_worker.ex
- Config for Oban" \
  --label "enhancement"

gh issue create --title "Portfolio value charts" \
  --body "Using Contex library:
- Total portfolio value over time
- Per-currency breakdown
- Individual holding performance
- Interactive date range selection

Consider adding:
- lib/dividendsomatic_web/live/charts_live.ex" \
  --label "enhancement"

gh issue create --title "Dividend tracking and projections" \
  --body "Features:
- Separate dividends table
- Import dividend history
- Calculate projected annual dividends
- Dividend yield per holding
- Payment schedule calendar

Database:
- Add dividends table (symbol, ex_date, pay_date, amount)
- Link to holdings" \
  --label "enhancement"

gh issue create --title "Deployment to production" \
  --body "Tasks:
- PostgreSQL setup (replace SQLite)
- Hetzner Cloud configuration
- Docker + Caddy setup
- Environment variables
- GitHub Actions CI/CD
- Database migrations strategy" \
  --label "deployment"

gh issue create --title "Testing suite" \
  --body "Add tests for:
- Portfolio context functions
- CSV import
- LiveView interactions
- Navigation logic
- Currency calculations

Target: >80% coverage" \
  --label "testing"

gh issue create --title "Error handling improvements" \
  --body "Add proper error handling:
- CSV import failures
- Invalid data format
- Database constraints
- User feedback messages
- Logging" \
  --label "enhancement"

gh issue create --title "Performance optimization" \
  --body "Optimize:
- Preload holdings in queries
- Add database indexes for common queries
- Lazy loading for large datasets
- Caching for summary calculations" \
  --label "performance"
```

## Quick create all at once

```bash
# You can run this after pushing to GitHub
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic
bash -c "$(cat GITHUB_ISSUES.md | grep '^gh issue create' | tr '\n' ' ')"
```
