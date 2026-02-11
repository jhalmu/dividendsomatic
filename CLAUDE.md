# CLAUDE.md - Dividendsomatic

Portfolio and dividend tracking system for Interactive Brokers CSV data. Phoenix LiveView application with DaisyUI components and fluid design tokens. Single-user app, no authentication.

## Security

- Never commit secrets or CSV data to git
- `.gitignore` covers `*.db`, `*.csv`, `.env`
- Required env vars (production): `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `FINNHUB_API_KEY`

## Commands

```bash
# Development
mix deps.get && mix ecto.setup    # First-time setup
mix phx.server                    # Start server (localhost:4000)
mix import.csv path/to/flex.csv   # Import CSV data

# Database
mix ecto.reset                    # Drop + create + migrate

# Testing
mix test                          # Run tests
mix precommit                     # compile + format + test
mix test.all                      # precommit + credo --strict

# Code quality
mix format                        # Format code
mix credo                         # Static analysis
mix sobelow                       # Security analysis
mix dialyzer                      # Type checking
```

## Architecture

### Stack
- Phoenix 1.8 + LiveView 1.1 + Ecto + PostgreSQL (dev & prod via docker-compose)
- DaisyUI 5.0 + Tailwind CSS v4 with fluid design tokens
- NimbleCSV, Contex (charts), Oban (background jobs), Req (HTTP)

### Contexts
- **Portfolio** - Snapshots, holdings, dividends, sold positions, CSV import
- **Stocks** - Stock quotes, company profiles (Finnhub API)
- **MarketSentiment** - Market sentiment data
- **Gmail** - Auto-fetch CSV attachments from Gmail

### Identifier Strategy

ISIN is the primary identifier (not symbol/ticker). Symbols can be reused/changed (e.g., TELIA).

Cascading lookup: `identifier_key = isin || figi || "symbol:exchange"`

### Key Modules

```
lib/dividendsomatic/
  portfolio.ex                    # Portfolio context
  portfolio/
    csv_parser.ex                 # Header-based CSV parser (Format A & B)
    portfolio_snapshot.ex         # Daily snapshot schema (immutable history)
    holding.ex                    # Individual holding schema
    dividend.ex                   # Dividend tracking schema
    sold_position.ex              # Sold positions schema
  stocks.ex                       # Stocks context
  stocks/
    stock_quote.ex                # Stock quote schema
    company_profile.ex            # Company profile schema
  data_ingestion/
    csv_directory.ex              # CSV directory adapter
    gmail_adapter.ex              # Gmail adapter
  market_sentiment.ex             # Market sentiment context
  gmail.ex                        # Gmail integration
  workers/
    gmail_import_worker.ex        # Oban worker for Gmail import

lib/dividendsomatic_web/
  live/
    portfolio_live.ex             # Main LiveView
    portfolio_live.html.heex      # LiveView template
    stock_live.ex                 # Stock detail LiveView
  components/
    portfolio_chart.ex            # Contex chart component
    core_components.ex            # Shared UI components
  router.ex                       # Routes

lib/mix/tasks/
  import_csv.ex                   # mix import.csv task
  import_batch.ex                 # mix import.batch task
  import_reimport.ex              # mix import.reimport (one-time re-import)
```

## Coding Conventions

### Elixir
- Context verbs: get, list, create, update, delete
- Schemas: PascalCase nouns (PortfolioSnapshot, Holding)
- Functions: snake_case | Modules: PascalCase | Atoms: :snake_case
- Use `Decimal` for all money values (never Float)
- Context pattern: no direct schema access from web layer

### LiveView
- Events: "navigate", "key" | Assigns: `@snapshot`, `@total_value`
- Templates: `.html.heex` | Use `phx-*` attributes for interactivity

### Database
- Tables: plural snake_case (portfolio_snapshots, holdings)
- Foreign keys: `{table_singular}_id` | Primary keys: binary_id (UUID)
- Timestamps: `inserted_at`, `updated_at`

### Design System
- Use fluid design tokens (`[var(--space-md)]`, `[var(--text-base)]`) instead of hardcoded Tailwind values
- DaisyUI component classes (`btn`, `card`, `table`) are semantic - don't tokenize them
- See [DESIGN_SYSTEM_GUIDE.md](DESIGN_SYSTEM_GUIDE.md) for full reference

## Claude Behavioral Rules

### Session Start
1. Read MEMO.md for latest session notes
2. Check GitHub issues: `gh issue list`

### EOD Workflow
When user says **"EOD"**: Execute immediately without confirmation:
1. Run `mix test.all`
2. Sync GitHub issues (`gh issue list/close/comment`)
3. Update SESSION_REPORT.md
4. Commit & push

Commands allowed without asking: `git`, `gh`, `mix test`, `mix format`, `mix credo`

### Commit Message Format
```
[type]: Short description

- Bullet points for changes
Fixes: #issue

Co-Authored-By: Claude <noreply@anthropic.com>
```
Types: feat, fix, docs, test, refactor, chore, security, perf

### Test Failures = STOP
If tests fail, stop and fix before proceeding. Never commit failing code.

### Design Principles
- KISS: Keep it simple
- DaisyUI components > custom CSS
- Design tokens > hardcoded values
- Decimal > Float for money
- Context pattern > direct schema access
- WCAG AA accessibility minimum

## Related Documentation

- [DESIGN_SYSTEM_GUIDE.md](DESIGN_SYSTEM_GUIDE.md) - Fluid design tokens, usage patterns, migration guide
- [MEMO.md](MEMO.md) - Session notes, current status, GitHub issues, technical debt
- [SESSION_REPORT.md](SESSION_REPORT.md) - Detailed session reports
- [AGENTS.md](AGENTS.md) - Agent guidelines and project patterns
- [GMAIL_OAUTH_SETUP.md](GMAIL_OAUTH_SETUP.md) - Gmail OAuth2 configuration guide
- [docs/PHOENIX_PATTERNS.md](docs/PHOENIX_PATTERNS.md) - Phoenix/LiveView/Ecto usage rules
- [docs/Rule72.md](docs/Rule72.md) - Rule of 72 reference
