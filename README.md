# Dividendsomatic

Portfolio and dividend tracking system for Interactive Brokers CSV statements.

## Features (MVP)

- ✅ CSV import from Interactive Brokers
- ✅ Daily portfolio snapshots
- ✅ All 18 CSV fields stored
- 🚧 LiveView portfolio viewer
- 🚧 Date navigation (arrow keys)
- 🚧 Charts (portfolio value over time)
- 🚧 Dividend tracking and projections

## Tech Stack

- **Phoenix 1.8.1** + **LiveView 1.1.0**
- **SQLite** (development)
- **DaisyUI** components
- **NimbleCSV** parser
- **Tailwind CSS v4** with design tokens

## Quick Start

```bash
# Setup
mix setup

# Import CSV
mix import.csv path/to/flex.csv

# Run server
mix phx.server
# Visit http://localhost:4000
```

## CSV Format

Interactive Brokers "Activity Flex" CSV with fields:
- ReportDate, CurrencyPrimary, Symbol, Description
- SubCategory, Quantity, MarkPrice, PositionValue
- CostBasisPrice, CostBasisMoney, OpenPrice
- PercentOfNAV, FifoPnlUnrealized, ListingExchange
- AssetClass, FXRateToBase, ISIN, FIGI

## Development

See [CLAUDE.md](CLAUDE.md) for detailed development guide.

See [SESSION_REPORT.md](SESSION_REPORT.md) for latest session notes.
