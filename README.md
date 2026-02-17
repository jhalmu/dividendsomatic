# Dividendsomatic

Portfolio and dividend tracking system for multi-broker data. Built with Phoenix LiveView, custom terminal-themed UI, and PostgreSQL.

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


## License

MIT
