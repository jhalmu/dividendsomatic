# Plan: Continuation Notes

Current state and future direction for Dividendsomatic.

---

## What's Implemented

### Working Features
- **CSV Import:** `mix import.csv path/to/file.csv` parses IB Activity Flex CSVs
- **Portfolio Viewer:** LiveView with arrow-key date navigation (First/Prev/Next/Last)
- **Holdings Table:** All 18 fields from IB export displayed with terminal theme
- **Portfolio Chart:** Contex SVG line chart showing portfolio value over time
- **Stats Cards:** Holdings count, total value, unrealized P&L
- **Dividend Tracking:** YTD dividends, projected annual, recent dividends list
- **Sold Positions:** What-if analysis comparing sale proceeds to hypothetical current value
- **Market Sentiment:** Fear & Greed Index from Alternative.me API (cached 1hr)
- **Gmail Integration:** Full implementation (needs OAuth credentials)
- **Terminal Theme:** Dark theme with JetBrains Mono, Outfit fonts, emerald accents

### Database
- SQLite for development, PostgreSQL planned for production
- Schemas: `portfolio_snapshots`, `holdings`, `dividends`, `sold_positions`
- All monetary values use `Decimal` (never Float)
- Binary UUID primary keys throughout

### Not Yet Working
- Oban disabled (SQLite lacks pub/sub for job notifications)
- Gmail import needs OAuth credentials configured
- Finnhub stock quotes need API key
- No production deployment

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Database | SQLite (dev) / PostgreSQL (prod) | Simple local dev, production-ready with Postgres |
| Charts | Contex (server-side SVG) | No JS dependencies, works with LiveView |
| Styling | DaisyUI 5 + custom terminal CSS | Semantic components + distinctive theme |
| Background jobs | Oban | Production-grade, but disabled until Postgres |
| HTTP client | Req | Modern, composable, built-in JSON |
| CSV parsing | NimbleCSV | Fast, configurable, Elixir-native |
| Money | Decimal | Exact arithmetic, no floating-point errors |

---

## Mock Data

Seeds file: `priv/repo/seeds.exs`

**To populate:**
```bash
mix ecto.reset && mix run priv/repo/seeds.exs
```

**What's included:**
- 60+ daily portfolio snapshots spanning ~3 months
- 7 holdings per snapshot with realistic price movements
- Dividend records (quarterly payments from multiple stocks)
- Sold positions for what-if analysis
- Varying portfolio values to create interesting chart shapes

**Use for:**
- Chart development and testing
- UI/UX design iterations
- Testing date navigation with many snapshots
- Verifying growth stats calculations

---

## Testing Strategy

### Current State
- 14 tests passing
- No LiveView tests (#8)
- No accessibility tests (#9)
- No mix task tests (#10)

### Target: 80% Coverage (#11)

**Priority order:**
1. **Portfolio context tests** -- CRUD operations, chart data, growth stats
2. **LiveView tests (#8)** -- Navigation, event handling, assign verification
3. **CSV import tests (#10)** -- Mix task, parsing edge cases, malformed data
4. **Accessibility tests (#9)** -- WCAG AA compliance with a11y_audit
5. **Integration tests** -- Full flow from CSV to rendered page

### Test Commands
```bash
mix test                    # Run all tests
mix test --cover            # With coverage report
mix test test/dividendsomatic/portfolio_test.exs  # Specific file
mix precommit               # compile + format + test
mix test.all                # precommit + credo --strict
```

---

## Production Deployment

### Requirements
- PostgreSQL database
- Environment variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`
- Optional: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`
- Optional: `FINNHUB_API_KEY`

### Deployment Options
1. **Fly.io** -- Simple, free tier available, good Phoenix support
2. **Railway** -- Easy Postgres provisioning
3. **Self-hosted** -- Docker + Kamal

### Steps
1. Switch to PostgreSQL adapter in prod config
2. Enable Oban (works with Postgres pub/sub)
3. Set up Gmail OAuth credentials
4. Configure Finnhub API key
5. Deploy with `mix phx.gen.release` or Docker

---

## Next Session Priorities

1. **Frontend redesign** -- Combined charts (value + dividends + P&L), better navigation
2. **Testing** -- Start with Portfolio context tests, then LiveView
3. **Mail.app integration** -- Local CSV import via AppleScript
4. **Credo cleanup** -- Fix 6 readability issues, address design suggestions

---

## Open GitHub Issues

| # | Title | Status |
|---|-------|--------|
| #5 | Testing Suite | Open |
| #8 | Add LiveView tests for PortfolioLive | Open |
| #9 | Add accessibility tests with a11y_audit | Open |
| #10 | Add Mix task tests for import.csv | Open |
| #11 | Increase overall test coverage to 80% | Open |
