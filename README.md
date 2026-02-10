# Dividendsomatic

Portfolio and dividend tracking system for Interactive Brokers. Built with Phoenix LiveView, custom terminal-themed UI, and PostgreSQL.

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
# Single CSV file
mix import.csv path/to/flex.csv

# Batch import from directory
mix import.batch path/to/csv_directory
```

## Features

- CSV import from Interactive Brokers Activity Flex reports
- Batch import from directory with duplicate detection
- Generic data ingestion pipeline (CSV directory + Gmail adapters)
- Automated daily import via Oban cron (weekdays 12:00)
- Portfolio viewer with date navigation (arrow keys)
- Custom SVG combined chart (value + cost basis + dividends)
- Chart animations (path drawing, pulsing markers)
- Circular Fear & Greed gauge (market sentiment)
- Holdings table with P&L highlighting
- Stock detail pages with external links (Yahoo, SeekingAlpha, Nordnet)
- Dividend and sold position tracking
- Stock quotes and company profiles (Finnhub API)
- WCAG AA accessible (axe-core tested)

## Tech Stack

- Phoenix 1.8 + LiveView 1.1
- PostgreSQL + Ecto
- Oban (background jobs + cron scheduling)
- Custom terminal-themed UI with fluid design tokens
- Tailwind CSS v4 + DaisyUI 5.0
- NimbleCSV, Contex (sparklines), Req (HTTP)

## Testing

```bash
mix test              # Run tests (180 tests)
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
| `GMAIL_CLIENT_ID` | optional | Gmail auto-import OAuth |
| `GMAIL_CLIENT_SECRET` | optional | Gmail auto-import OAuth |

## License

MIT
