# Dividendsomatic

Portfolio and dividend tracking system for Interactive Brokers. Built with Phoenix LiveView, DaisyUI, and SQLite.

## Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Visit http://localhost:4000

## Import Data

```bash
mix import.csv path/to/flex.csv
```

## Features

- CSV import from Interactive Brokers Activity Flex reports
- Portfolio viewer with date navigation (arrow keys)
- Holdings table with P&L highlighting
- Dividend and sold position tracking
- Stock quotes and company profiles (Finnhub)
- Portfolio value charts (Contex)
- Gmail auto-import (Oban worker)
- Market sentiment data

## Tech Stack

- Phoenix 1.8 + LiveView 1.1
- SQLite (dev) / PostgreSQL (prod)
- DaisyUI 5.0 + Tailwind CSS v4
- NimbleCSV, Contex, Oban, Req

## Testing

```bash
mix test              # Run tests
mix test.all          # Tests + credo
```

## License

MIT
