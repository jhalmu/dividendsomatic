# CLAUDE.md - Dividendsomatic Development Guide

## 📋 Projektin Kuvaus
Portfolio ja osinko-seurantajärjestelmä Interactive Brokers CSV-tiedostoille. Phoenix LiveView -sovellus DaisyUI-komponenteilla.

## 🎯 Projektin Tila: MVP VALMIS ✅

**Valmiit ominaisuudet:**
- CSV import (`mix import.csv`)
- LiveView portfolio viewer
- Nuolinäppäin-navigointi (← →)
- Holdings-taulukko P&L-korostuksilla
- Kaikki 18 CSV-kenttää tietokannassa

**Seuraavana:**
- Gmail MCP integraatio (automaattinen CSV haku)
- Oban worker (päivittäinen ajastus)
- Contex grafiikat (portfolio arvo ajan yli)

## 🛠 Tekniset Valinnat

### Core Stack
- **Phoenix 1.8.3** + **LiveView 1.1.22**
- **Ecto 3.13.4** + **SQLite** (dev) / **PostgreSQL** (prod)
- **NimbleCSV 1.3** - CSV parsing
- **DaisyUI 5.0** - UI components
- **Tailwind CSS v4** - Styling with design tokens

### Libraries
- `phoenix` ~> 1.8.3
- `phoenix_live_view` ~> 1.1.22
- `ecto_sql` ~> 3.13.4
- `ecto_sqlite3` ~> 0.22.0
- `nimble_csv` ~> 1.3.0
- `decimal` ~> 2.3 (for precise money calculations)

## 📁 Tiedostorakenne

```
dividendsomatic/
├── lib/
│   ├── dividendsomatic/              # Business logic
│   │   ├── portfolio.ex              # Portfolio context
│   │   └── portfolio/
│   │       ├── portfolio_snapshot.ex # Daily snapshot schema
│   │       └── holding.ex            # Individual holding schema
│   ├── dividendsomatic_web/          # Web interface
│   │   ├── live/
│   │   │   ├── portfolio_live.ex     # Main LiveView
│   │   │   └── portfolio_live.html.heex
│   │   └── router.ex
│   └── mix/tasks/
│       └── import_csv.ex             # CSV import task
├── priv/repo/migrations/
│   └── *_create_portfolio_system.exs
├── assets/
│   ├── css/app.css                   # Design tokens
│   └── vendor/                       # DaisyUI, Heroicons
├── CLAUDE.md                         # This file
├── SESSION_REPORT.md                 # Session notes
├── GITHUB_ISSUES.md                  # Issue tracker
└── README.md                         # User documentation
```

## 🗄 Tietokanta

### Taulut

**portfolio_snapshots**
```elixir
- id: binary_id (UUID)
- report_date: date (unique)
- raw_csv_data: text (backup)
- inserted_at, updated_at: timestamps
```

**holdings**
```elixir
- id: binary_id (UUID)
- portfolio_snapshot_id: binary_id (FK → portfolio_snapshots)
- report_date: date
- currency_primary: string (EUR, USD)
- symbol: string (KESKOB, EPR, etc.)
- description: string
- sub_category: string (COMMON, REIT)
- quantity: decimal
- mark_price: decimal
- position_value: decimal
- cost_basis_price: decimal
- cost_basis_money: decimal
- open_price: decimal
- percent_of_nav: decimal
- fifo_pnl_unrealized: decimal
- listing_exchange: string (HEX, NYSE, NASDAQ)
- asset_class: string (STK)
- fx_rate_to_base: decimal
- isin: string
- figi: string
- inserted_at, updated_at: timestamps
```

**Indeksit:**
- `portfolio_snapshots_report_date_index` (unique)
- `holdings_portfolio_snapshot_id_index`
- `holdings_symbol_index`
- `holdings_report_date_index`

## 💻 Context Pattern

**Dividendsomatic.Portfolio** tarjoaa:

```elixir
# Navigation
get_latest_snapshot() :: PortfolioSnapshot.t() | nil
get_snapshot_by_date(Date.t()) :: PortfolioSnapshot.t() | nil
get_previous_snapshot(Date.t()) :: PortfolioSnapshot.t() | nil
get_next_snapshot(Date.t()) :: PortfolioSnapshot.t() | nil

# Import
create_snapshot_from_csv(csv_data :: String.t(), report_date :: Date.t())
  :: {:ok, PortfolioSnapshot.t()} | {:error, term()}

# Listing
list_snapshots() :: [PortfolioSnapshot.t()]
```

## 🎨 DaisyUI Komponentit

**Käytä näitä:**

```heex
<!-- Navigation buttons -->
<button class="btn btn-circle btn-outline">←</button>
<button class="btn btn-circle btn-outline">→</button>

<!-- Summary card -->
<div class="card bg-base-200">
  <div class="card-body">
    <h2 class="card-title">Title</h2>
    <p>Content</p>
  </div>
</div>

<!-- Holdings table -->
<table class="table table-zebra">
  <thead>
    <tr><th>Symbol</th><th>Value</th></tr>
  </thead>
  <tbody>
    <tr><td>KESKOB</td><td>21000</td></tr>
  </tbody>
</table>

<!-- Color highlighting -->
<span class={["font-semibold", 
  if(positive?, do: "text-success", else: "text-error")]}>
  <%= value %>
</span>
```

## 🎨 Design Tokens

**CSS Custom Properties (homesite-tyyli):**

```css
/* Spacing */
gap-[var(--space-xs)]    /* 0.25-0.5rem */
gap-[var(--space-sm)]    /* 0.5-1rem */
gap-[var(--space-md)]    /* 1-2rem */
gap-[var(--space-lg)]    /* 2-4rem */
p-[var(--space-md)]      /* padding */

/* Typography */
text-[var(--text-xs)]    /* 0.75-0.875rem */
text-[var(--text-base)]  /* 1-1.25rem */
text-[var(--text-lg)]    /* 1.125-1.5rem */
text-[var(--text-xl)]    /* 1.25-2rem */
text-[var(--text-2xl)]   /* 1.5-3rem */
```

## ⌨️ Komennot

### Development
```bash
# Setup
mix deps.get
mix ecto.setup

# CSV import
mix import.csv path/to/flex.csv

# Server
mix phx.server              # http://localhost:4000
iex -S mix phx.server       # with IEx console

# Database
mix ecto.create
mix ecto.migrate
mix ecto.reset              # Drop, create, migrate, seed

# Code quality
mix compile                 # Check compilation
mix format                  # Format code
mix credo                   # Static analysis
mix sobelow                 # Security analysis
mix deps.audit              # Dependency vulnerabilities
mix dialyzer                # Type checking (slow first run)
```

### Testing
```bash
mix test                    # Run tests
mix test --cover            # With coverage
mix precommit               # compile + unlock + format + test
mix test.all                # precommit + credo --strict
mix test.full               # test.all (full suite)
```

### Production (TODO)
```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix ecto.migrate
MIX_ENV=prod mix phx.server
```

## 🔧 CSV Import Process

**Workflow:**

1. Käyttäjä lataa CSV Interactive Brokersista
2. Suorittaa: `mix import.csv path/to/file.csv`
3. Task lukee CSV:n
4. NimbleCSV parsii rivit
5. Luo `PortfolioSnapshot` transaction:ssa
6. Luo `Holding`-rivit jokaiselle omistukselle
7. Palauttaa success/error

**CSV Format:**
```csv
"ReportDate","CurrencyPrimary","Symbol","Description",...
"2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS",...
```

## 🎯 Seuraavat Tehtävät

### Priority 1: Gmail Automation
```bash
# Install Gmail MCP
# Add to config/config.exs

# Implement auto-import
lib/dividendsomatic/importers/gmail_importer.ex

# Schedule with Oban
lib/dividendsomatic/workers/csv_import_worker.ex
```

### Priority 2: Charts
```elixir
# Add Contex
{:contex, "~> 0.5"}

# Create chart component
lib/dividendsomatic_web/live/components/portfolio_chart.ex
```

### Priority 3: Dividends
```bash
# Migration
mix ecto.gen.migration create_dividends

# Schema & Context
lib/dividendsomatic/portfolio/dividend.ex
```

## 🐛 Debugging Tips

**Common Issues:**

1. **NimbleCSV parse error**: Check CSV encoding (must be UTF-8)
2. **Decimal precision**: Always use `Decimal.new/1` for money
3. **Foreign key**: Use `portfolio_snapshot_id`, not `snapshot_id`
4. **LiveView not updating**: Check `phx-*` attributes
5. **DaisyUI not working**: Check vendor files in assets/

**IEx Helpers:**
```elixir
# In iex -S mix phx.server
alias Dividendsomatic.{Repo, Portfolio}
alias Dividendsomatic.Portfolio.{PortfolioSnapshot, Holding}

# Get latest snapshot
Portfolio.get_latest_snapshot() |> Repo.preload(:holdings)

# Count holdings
Repo.aggregate(Holding, :count)

# Check snapshots
Portfolio.list_snapshots()
```

## 📝 Koodauskonventiot

### Elixir
- **Context**: Verbit (get, list, create, update, delete)
- **Schemas**: Substantiivit (PortfolioSnapshot, Holding)
- **Functions**: snake_case
- **Modules**: PascalCase
- **Atoms**: :snake_case

### LiveView
- **Events**: "navigate", "key", etc.
- **Assigns**: `@snapshot`, `@total_value`
- **Templates**: `.html.heex` extension
- **Hooks**: `phx-*` attributes

### Database
- **Tables**: plural (portfolio_snapshots, holdings)
- **Columns**: snake_case
- **Foreign Keys**: `{table_singular}_id`
- **Primary Keys**: `id` (binary_id UUID)
- **Timestamps**: `inserted_at`, `updated_at`

## 🔒 Turvallisuus

**Huomioitavaa:**

1. **CSV Data**: Käyttäjän yksityistä taloustietoa → ei git:iin
2. **Database**: SQLite dev:ssä, PostgreSQL prod:ssa
3. **Auth**: Ei vielä toteutettu (single user)
4. **CSRF**: Phoenix hoitaa automaattisesti
5. **SQL Injection**: Ecto parametrisoi kyselyt

**.gitignore sisältää:**
```
*.db
*.db-shm
*.db-wal
*.csv
```

## 📚 Resurssit

**Phoenix & LiveView:**
- https://hexdocs.pm/phoenix/overview.html
- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html

**DaisyUI:**
- https://daisyui.com/components/

**NimbleCSV:**
- https://hexdocs.pm/nimble_csv/NimbleCSV.html

**Decimal:**
- https://hexdocs.pm/decimal/Decimal.html

## 🤖 Claude Behavioral Rules

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

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>
```
Types: feat, fix, docs, test, refactor, chore, security, perf

### Test Failures = STOP

If tests fail, stop and fix before proceeding. Never commit failing code.

## 🤖 AI Assistant Notes

**Tämä projekti on:**
- MVP-vaiheessa (toimiva, mutta basic)
- Yhden käyttäjän sovellus (ei auth)
- Kehitystyökaluna käytetty Claude Code
- Design patterns: homesite-projektista
- Testaaminen: manuaalista (testit TODO)

**Kehitysfilosofia:**
- KISS (Keep It Simple)
- MVP first, features later
- DaisyUI components > custom CSS
- Design tokens > hard-coded values
- NimbleCSV > String.split
- Decimal > Float (money)
- Context pattern > direct schema access

**Kun jatkokehität:**
1. Lue ensin GITHUB_ISSUES.md
2. Lue SESSION_REPORT.md viimeisimmät muutokset
3. Testaa muutokset: `mix compile`
4. Päivitä dokumentit
5. Commitoi kuvaavalla viestillä

---

**Version:** 0.1.0 (MVP)
**Last Updated:** 2026-01-30
**Status:** 🟢 Fully Functional MVP
