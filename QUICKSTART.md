# 🚀 Quickstart - Dividendsomatic

Get up and running in 5 minutes!

## Prerequisites

- Elixir 1.15+
- Phoenix 1.8+
- PostgreSQL (production) or SQLite (development)

## Installation

```bash
# Clone repo
git clone https://github.com/jhalmu/dividendsomatic.git
cd dividendsomatic

# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Install assets
cd assets && npm install && cd ..
```

## Import Your First CSV

```bash
# Download your Interactive Brokers "Activity Flex" CSV
# Then import it:
mix import.csv path/to/your/flex.csv

# Example:
mix import.csv ~/Downloads/flex.490027.PortfolioForWww.20260128.20260128.csv
```

## Start Server

```bash
mix phx.server
```

Visit: **http://localhost:4000**

## Usage

### Navigation
- **Arrow Left (←)** - Previous day
- **Arrow Right (→)** - Next day
- **Click navigation buttons** - Same as arrows

### Features
- View latest portfolio snapshot
- See holdings grouped by currency
- Track unrealized P&L (color-coded)
- Navigate between different days

## CSV Format

Your CSV should be from Interactive Brokers "Activity Flex" reports with these columns:

```
ReportDate, CurrencyPrimary, Symbol, Description, SubCategory,
Quantity, MarkPrice, PositionValue, CostBasisPrice, CostBasisMoney,
OpenPrice, PercentOfNAV, FifoPnlUnrealized, ListingExchange,
AssetClass, FXRateToBase, ISIN, FIGI
```

## Common Tasks

### Reset database
```bash
mix ecto.reset
```

### Import multiple CSV files
```bash
for file in ~/Downloads/flex*.csv; do
  mix import.csv "$file"
done
```

### View all snapshots
```elixir
# In iex -S mix
Dividendsomatic.Portfolio.list_snapshots()
```

## Troubleshooting

### "No Portfolio Data" shown?
- Make sure you've imported a CSV first
- Check that CSV has the correct format
- Run `mix import.csv` again

### Database issues?
```bash
mix ecto.reset  # This will recreate everything
```

### Server not starting?
```bash
mix deps.get
mix compile
```

## Next Steps

1. ✅ Import your CSV files
2. ✅ Browse your portfolio
3. 📊 Set up automated imports (see TODO.md)
4. 📈 Add charts (see TODO.md)
5. 💰 Track dividends (see TODO.md)

## Documentation

- [README.md](README.md) - Project overview
- [CLAUDE.md](CLAUDE.md) - Development guide
- [TODO.md](TODO.md) - Feature roadmap
- [SESSION_REPORT.md](SESSION_REPORT.md) - Latest changes

## Need Help?

Check:
1. [GitHub Issues](https://github.com/jhalmu/dividendsomatic/issues)
2. CLAUDE.md for technical details
3. SESSION_REPORT.md for latest updates

---

**Happy investing! 📈💰**
