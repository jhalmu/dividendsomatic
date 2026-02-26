# Dividendsomatic

Portfolio and dividend tracking dashboard. Data is based on combined real data for testing purposes. Built with Phoenix LiveView, custom terminal-themed UI, and PostgreSQL.

## Features

- **Multiple CSV formats and tax reports** with automated daily import
- **Unified portfolio history:** All sources write to one schema, no runtime reconstruction
- **Portfolio viewer:** Date navigation (arrow keys), date picker, year filters
- **Interactive charts:** Portfolio value, dividend history with monthly + cumulative views
- **Investment summary:** Net invested, realized/unrealized P&L, dividends, costs, total return
- **Dividend analytics:** Per-year tracking, cash flow, projections, per-symbol breakdown
- **Realized P&L:** Grouped by symbol, year filters, top winners/losers, EUR conversion
- **Multi-provider market data** with fallback chains
- **Fear & Greed gauge:** Market sentiment with 365-day history
- **Stock detail pages:** External links to financial data providers
- **Data coverage page:** Source timelines, per-stock gaps, dividend gaps
- **FX exposure:** Currency breakdown with EUR conversion
- **WCAG AA accessible** (axe-core tested)

## Tech Stack

- Phoenix 1.8 + LiveView 1.1
- PostgreSQL + Ecto
- Oban (background jobs + cron scheduling)
- Custom terminal-themed UI with fluid design tokens
- Tailwind CSS v4 + DaisyUI 5.0
- NimbleCSV, Contex (sparklines), Req (HTTP)


## Code Quality

- Tests: 696 passing
- Credo: 0 issues (strict mode)
- Lighthouse: 96 accessibility, 100 best practices, 100 SEO
- Sobelow: clean (low-confidence only)
- axe-core: WCAG AA passing

## License

MIT
