# AGENTS.MD - Dividendsomatic Project Guidelines

This is a Phoenix LiveView application for portfolio tracking.

## Core Principles

### Simplicity First
- **No megalomania**: Build features that are actually needed
- **Complete features**: Finish one thing before starting another
- **Test immediately**: No deferred testing

### Code Quality
- `mix format` before every commit
- Follow Elixir conventions (snake_case, pattern matching)

## Project Guidelines

### HTTP Requests
Use `:req` (Req) library - already included
Avoid: `:httpoison`, `:tesla`, `:httpc`

### CSV Parsing
Use `NimbleCSV` - lightweight, fast
Pattern: parse → validate → insert batch

### Session Workflow

#### Starting
1. Read MEMO.md (latest session notes)
2. Check GitHub issues: `gh issue list`

#### During
- Work systematically
- Test as you go: `mix test`
- Keep changes small and focused

#### Ending
1. Update MEMO.md with timestamp and summary
2. Run `mix test`
3. Commit with clear message
4. Push to preserve work

## Architecture

### Contexts
- **Portfolio** - Snapshots, holdings, dividends, sold positions, CSV import
- **Stocks** - Stock quotes, company profiles (Finnhub API)
- **MarketSentiment** - Market sentiment data
- **Gmail** - Auto-fetch CSV attachments from Gmail

### No Scoping
Single-user app, no authentication needed

### Database Design
- Snapshots: One per report date
- Holdings: Many per snapshot
- Dividends: Per holding per date
- Sold positions: Completed trades
- Stock quotes: Market data cache
- Keep raw CSV for audit

## Phoenix/LiveView Patterns

### LiveView Components
```elixir
# Use function components
def portfolio_card(assigns) do
  ~H"""
  <div class="card">
    <%= @content %>
  </div>
  """
end
```

### Forms
Use `to_form/2`, access fields with `@form[:field]`

### Navigation
`<.link navigate={...}>` (not deprecated `live_redirect`)

## DaisyUI Usage

Maximize DaisyUI components:
- `btn`, `btn-primary`, `btn-ghost`
- `card`, `card-body`
- `table`, `table-zebra`
- `stats`, `stat`
- `badge`

Use design tokens from Homesite when needed:
- `[var(--space-md)]` for spacing
- `[var(--text-base)]` for typography

## Testing

```bash
mix test              # Run tests
mix format            # Format code
```

## Git Workflow

```bash
git add .
git commit -m "feat: description"
git push
```

Commit format: `feat:`, `fix:`, `docs:`, `refactor:`

## Key Design Decisions

1. **Snapshot architecture**: Immutable daily records
2. **Raw CSV storage**: Audit trail preservation
3. **DaisyUI first**: Leverage component library
4. **Arrow navigation**: Simple date browsing
5. **No authentication**: Local single-user app

## File Organization

```
lib/dividendsomatic/
  portfolio.ex                  # Portfolio context
  portfolio/
    portfolio_snapshot.ex       # Daily snapshot schema
    holding.ex                  # Individual holding schema
    dividend.ex                 # Dividend tracking schema
    sold_position.ex            # Sold positions schema
  stocks.ex                     # Stocks context
  stocks/
    stock_quote.ex              # Stock quote schema
    company_profile.ex          # Company profile schema
  market_sentiment.ex           # Market sentiment context
  gmail.ex                      # Gmail integration
  data_ingestion.ex             # Generic data ingestion behaviour
  data_ingestion/
    csv_directory.ex            # CSV directory source adapter
    gmail_adapter.ex            # Gmail source adapter
    normalizer.ex               # CSV normalizer
  workers/
    gmail_import_worker.ex      # Oban worker for Gmail import
    data_import_worker.ex       # Oban worker for generic data import

lib/dividendsomatic_web/
  live/
    portfolio_live.ex           # Main LiveView
    portfolio_live.html.heex    # LiveView template
    stock_live.ex               # Stock detail page
  components/
    portfolio_chart.ex          # SVG chart components
    core_components.ex          # Shared UI components
  router.ex                     # Routes

lib/mix/tasks/
  import_csv.ex                 # mix import.csv task
  import_batch.ex               # mix import.batch task
```

## Remember

- Test after each significant change
- Keep functions small and focused
- Use pattern matching over conditionals
- Commit early, commit often
