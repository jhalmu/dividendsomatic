# Dividendsomatic - Quick Start Guide

## 🎯 What is this?

Portfolio tracking for Interactive Brokers CSV files. Built with Phoenix LiveView.

## ⚡ 5-Minute Setup

### 1. Install (MacOS/Linux)
```bash
# Clone
git clone https://github.com/jhalmu/dividendsomatic.git
cd dividendsomatic

# Setup
mix deps.get
mix ecto.setup

# Start
mix phx.server
```

Open: http://localhost:4000

### 2. Import Your Data
```bash
# Get CSV from Interactive Brokers:
# Reports → Flex Queries → Activity Flex → Generate

# Import
mix import.csv ~/Downloads/flex.490027.PortfolioForWww.20260128.20260128.csv
```

### 3. View Portfolio
- Navigate: **←** **→** arrow keys
- See holdings, P&L, totals

## 📥 Getting Your CSV

### Interactive Brokers Portal
1. Login → **Reports** → **Flex Queries**
2. Create new: **Activity Flex**
3. Select: **Portfolio**
4. Period: **Daily**
5. Format: **CSV**
6. Generate → Download

### CSV Location
Usually downloads to:
- MacOS: `~/Downloads/flex.*.csv`
- Windows: `C:\Users\YourName\Downloads\flex.*.csv`

## 🎮 Basic Usage

### Import Multiple Days
```bash
# Import each day
mix import.csv flex.20260128.csv
mix import.csv flex.20260127.csv
mix import.csv flex.20260126.csv

# Or batch import
for f in ~/Downloads/flex.*.csv; do
  mix import.csv "$f"
done
```

### Navigation
- **Home** → Latest portfolio
- **←** Previous day
- **→** Next day

### View Data
- Total portfolio value
- Individual holdings
- Profit/Loss per position
- Currency breakdown (EUR/USD)

## 🔧 Troubleshooting

### "Mix not found"
Install Elixir:
```bash
# MacOS
brew install elixir

# Ubuntu/Debian
sudo apt-get install elixir

# Or: https://elixir-lang.org/install.html
```

### "Database error"
Reset database:
```bash
mix ecto.reset
# Then re-import your CSV files
```

### "CSV parse error"
Check:
- File is Activity Flex format (not another report)
- File encoding is UTF-8
- File is not corrupted

### "Port 4000 in use"
Change port:
```bash
PORT=4001 mix phx.server
```

## 📚 Next Steps

### Automation (Coming Soon)
- Gmail auto-import
- Daily schedule
- Email notifications

### Analytics (Coming Soon)
- Portfolio charts
- Asset allocation
- P&L timeline

### Dividends (Coming Soon)
- Dividend tracking
- Yield calculator
- Future projections

## 🆘 Need Help?

**Check documentation:**
- [README.md](README.md) - Full documentation
- [CLAUDE.md](CLAUDE.md) - Development guide
- [GITHUB_ISSUES.md](GITHUB_ISSUES.md) - Roadmap

**Issues?**
- Open issue: https://github.com/jhalmu/dividendsomatic/issues
- Check logs: Look at terminal output
- Debug: Add `require IEx; IEx.pry` in code

## 💡 Tips

1. **Import Order**: Import oldest → newest for best navigation
2. **Daily Routine**: Download + import each day
3. **Backup**: Keep CSV files as backup
4. **Performance**: SQLite handles 100s of days easily

## ⚙️ Advanced

### Database Location
```bash
# Development
ls dividendsomatic_dev.db

# View tables
sqlite3 dividendsomatic_dev.db ".tables"

# Count holdings
sqlite3 dividendsomatic_dev.db "SELECT COUNT(*) FROM holdings;"
```

### Custom Port
```bash
# config/dev.exs
http: [ip: {127, 0, 0, 1}, port: 4001]
```

### Add Test Data
```elixir
# In iex -S mix
alias Dividendsomatic.{Repo, Portfolio}
csv = File.read!("path/to/flex.csv")
Portfolio.create_snapshot_from_csv(csv, ~D[2026-01-28])
```

## 🚀 Production Deploy

See [DEPLOYMENT.md](DEPLOYMENT.md) for:
- Fly.io deployment
- Railway deployment
- PostgreSQL setup
- SSL configuration

---

**Questions?** Open an issue on GitHub  
**Feedback?** PRs welcome!  
**Status:** ✅ MVP Working
