# Dividendsomatic 📊

Portfolio and dividend tracking system for Interactive Brokers CSV statements.

## 🚀 Features

### ✅ MVP (Implemented)
- **CSV Import**: Import Interactive Brokers Activity Flex CSV files
- **Portfolio Viewer**: LiveView-based portfolio viewer with DaisyUI
- **Date Navigation**: Arrow keys (← →) to navigate between dates
- **Holdings Display**: Table showing all positions with P&L highlighting
- **All Fields**: Stores all 18 CSV fields from Interactive Brokers

### 🚧 Coming Soon
- **Auto-Import**: Gmail MCP integration for automatic CSV fetching
- **Charts**: Portfolio value and P&L visualizations (Contex)
- **Dividends**: Track dividends and calculate yield
- **Alerts**: Email notifications for portfolio changes
- **Multi-User**: Authentication and multi-user support

## 🛠 Tech Stack

- **Phoenix 1.8.1** + **LiveView 1.1.0**
- **SQLite** (development) → **PostgreSQL** (production)
- **DaisyUI 5.0** for UI components
- **NimbleCSV** for CSV parsing
- **Tailwind CSS v4** with design tokens

## 📦 Installation

```bash
# Clone repository
git clone https://github.com/jhalmu/dividendsomatic.git
cd dividendsomatic

# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Install assets
cd assets && npm install && cd ..

# Start server
mix phx.server
```

Visit http://localhost:4000

## 📥 CSV Import

Import your Interactive Brokers Activity Flex CSV:

```bash
mix import.csv path/to/flex.490027.PortfolioForWww.20260128.20260128.csv
```

The CSV should have these fields:
- ReportDate, CurrencyPrimary, Symbol, Description
- SubCategory, Quantity, MarkPrice, PositionValue
- CostBasisPrice, CostBasisMoney, OpenPrice
- PercentOfNAV, FifoPnlUnrealized, ListingExchange
- AssetClass, FXRateToBase, ISIN, FIGI

## 🎮 Usage

### Portfolio Viewer
- Navigate to http://localhost:4000
- Use **←** and **→** arrow keys to navigate between dates
- Click navigation buttons for the same functionality
- View total portfolio value and individual holdings

### Keyboard Shortcuts
- `←` Previous date
- `→` Next date

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)** - Development guide for AI assistants
- **[MEMO.md](MEMO.md)** - Session notes and progress tracking
- **[GitHub Issues](https://github.com/jhalmu/dividendsomatic/issues)** - Planned features and bugs

## 🏗 Project Structure

```
lib/
├── dividendsomatic/
│   ├── portfolio.ex              # Context for portfolio operations
│   └── portfolio/
│       ├── portfolio_snapshot.ex # Schema for daily snapshots
│       └── holding.ex            # Schema for individual holdings
├── dividendsomatic_web/
│   ├── live/
│   │   └── portfolio_live.ex     # Main portfolio viewer
│   └── router.ex
└── mix/tasks/
    └── import_csv.ex             # CSV import task
```

## 🧪 Testing

```bash
# Run tests
mix test

# Full test suite with credo
mix test.all

# Check compilation
mix compile

# Code formatting
mix format
```

## 🚢 Deployment

### Development
```bash
mix phx.server
```

### Production (TODO)
```bash
# Setup PostgreSQL
mix ecto.create

# Compile assets
mix assets.deploy

# Start server
MIX_ENV=prod mix phx.server
```

## 📈 Roadmap

See [GitHub Issues](https://github.com/jhalmu/dividendsomatic/issues) for detailed roadmap.

### Phase 1: MVP ✅
- CSV import
- LiveView portfolio viewer
- Basic navigation

### Phase 2: Automation
- [#1](https://github.com/jhalmu/dividendsomatic/issues/1) Gmail MCP integration
- [#2](https://github.com/jhalmu/dividendsomatic/issues/2) Oban scheduling

### Phase 3: Analytics
- [#3](https://github.com/jhalmu/dividendsomatic/issues/3) Portfolio value charts
- [#4](https://github.com/jhalmu/dividendsomatic/issues/4) Dividend tracking

### Phase 4: Production
- [#5](https://github.com/jhalmu/dividendsomatic/issues/5) Testing suite
- [#6](https://github.com/jhalmu/dividendsomatic/issues/6) Production deployment

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- Built with [Phoenix Framework](https://phoenixframework.org/)
- UI components by [DaisyUI](https://daisyui.com/)
- CSV parsing by [NimbleCSV](https://github.com/dashbitco/nimble_csv)
- Design inspiration from [Homesite](https://github.com/jhalmu/homesite)

## 🤖 Built with Claude

This project was built with the assistance of Claude (Anthropic), using modern Phoenix LiveView patterns and best practices.

---

**Status**: 🟢 MVP Complete | **Version**: 0.1.0 | **Last Updated**: 2026-01-30
