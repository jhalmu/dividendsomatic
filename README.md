# Dividendsomatic

Portfolio and dividend tracking system for multi-broker data (Interactive Brokers, Nordnet). Built with Phoenix LiveView, custom terminal-themed UI, and PostgreSQL.

## Setup

```bash
docker compose up -d          # Start PostgreSQL
mix deps.get
mix ecto.setup
mix phx.server
```

Visit http://localhost:4000

## Import Data

```bash
# IBKR Activity Flex CSV
mix import.csv path/to/flex.csv

# Batch import from directory
mix import.batch path/to/csv_directory

# Nordnet transactions
mix import.nordnet

# Nordnet 9A tax report (sold positions)
mix import.nordnet --9a path/to/9a.csv

# IBKR transactions
mix import.ibkr

# Historical prices (Yahoo Finance)
mix fetch.historical_prices
```

## Features

- **Multi-broker import:** IBKR Flex CSV, Nordnet CSV, Lynx 9A tax reports
- **Automated daily import:** AppleScript email fetcher + Oban cron (weekdays)
- **Unified portfolio history:** All sources write to one schema, no runtime reconstruction
- **Portfolio viewer:** Date navigation (arrow keys), date slider, year filters
- **Custom SVG charts:** Portfolio value + cost basis lines, era-aware gap rendering
- **Separate dividend chart:** Monthly bars + cumulative line with year-aware labels
- **Investment summary:** Net invested, realized/unrealized P&L, dividends, costs, total return
- **Dividend analytics:** Per-year tracking, cash flow, projections, IEx diagnostics
- **Realized P&L:** Grouped by symbol, year filters, top winners/losers, EUR conversion
- **Market data:** Multi-provider (Finnhub + Yahoo Finance + EODHD) with fallback chains
- **Fear & Greed gauge:** Market sentiment with 365-day history
- **Stock detail pages:** External links (Yahoo, SeekingAlpha, Nordnet)
- **Data coverage page:** Broker timelines, per-stock gaps, dividend gaps
- **FX exposure:** Currency breakdown with EUR conversion
- **Chart animations:** Path drawing, pulsing markers
- **WCAG AA accessible** (axe-core tested)

## Tech Stack

- Phoenix 1.8 + LiveView 1.1
- PostgreSQL + Ecto
- Oban (background jobs + cron scheduling)
- Custom terminal-themed UI with fluid design tokens
- Tailwind CSS v4 + DaisyUI 5.0
- NimbleCSV, Contex (sparklines), Req (HTTP)

## Testing

```bash
mix test              # Run tests (447 tests)
mix precommit         # compile --warnings-as-errors + format + test
mix test.all          # precommit + credo --strict
```

## Code Quality

```bash
mix format                          # Format code
mix credo --strict                  # Static analysis
mix sobelow                         # Security analysis
mix dialyzer                        # Type checking
mix compile --warnings-as-errors    # Compiler warnings check
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | prod | PostgreSQL connection URL |
| `FINNHUB_API_KEY` | optional | Stock quotes & company profiles |
| `EODHD_API_KEY` | optional | Historical data & company profiles |
| `GMAIL_CLIENT_ID` | optional | Gmail auto-import OAuth |
| `GMAIL_CLIENT_SECRET` | optional | Gmail auto-import OAuth |

## License

MIT
