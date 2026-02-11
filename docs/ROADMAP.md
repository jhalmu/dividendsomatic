# Dividendsomatic Evolution Plan

> **Status: Phases 1-5 COMPLETE** (2026-02-10). 180 tests, 0 failures, 0 credo issues.
> Only #22 (Multi-provider market data architecture) remains open.

## Context

The app has matured from MVP to a working portfolio tracker with 125 tests, terminal-themed dark UI, custom SVG charts, and keyboard navigation. Now it needs a major evolution:

- **Richer UI**: F&G in chart background, dual navigation with decorative SVGs, enhanced dividend charts, animations
- **PostgreSQL**: Switch from SQLite to enable Oban scheduling and scale for production
- **Generic data pipeline**: Replace Gmail-specific import with source-agnostic ingestion (CSV directory, future IBKR API, etc.)
- **Stock detail pages**: Each holding links to its own view with company info, history, external links
- **Market data research**: Document which APIs support Finnish, Japanese, HK, Chinese stocks

Current data flow: GetLynxPortfolio app → Mail.app → Automator → `csv_data/` folder → manual `mix import.csv`. Goal: automate with daily 12:00 Oban cron job.

---

## Phase 1: UI Overhaul (DONE)

### 1.1 New Template Layout

Current order:
```
Brand ("dividends-o-matic")
Full Navigation (first/prev/date/next/last)
Stats Row (Portfolio Value, P&L, Dividends YTD, Holdings)
Combined Chart (value + cost basis + dividends + F&G bar)
Recent Dividends + Realized P&L (side-by-side cards)
Holdings Table (Positions)
Footer (keyboard hints)
```

New order:
```
Brand + fixed tagline + decorative rose line
Compact nav (thin, rosy SVG flourishes flanking the date)
Stats Row (4 cards, unchanged)
Compact nav (before chart)
Combined Chart (with F&G colored background band)
Compact nav (after chart)
Holdings Table + F&G gauge in header
Enhanced Dividends (filled area line chart with sum points)
Realized P&L
Footer
```

**Files**: `portfolio_live.html.heex`, `portfolio_live.ex`, `app.css`

### 1.2 Brand Area Redesign

The brand area gets a fixed tagline and decorative separation line.

**Tagline**: A permanent minimal tagline below the brand name. Options:
- "patience is profit"
- "sisu & dividends"
- "compound with patience"

Displayed in small italic dim mono font. Simple string in the template.

**Decorative SVG**: Thin rose-colored (`#f43f5e`, opacity 0.3) flowing curve line spanning full width, ~12px tall. Separates brand from content. Hand-drawn organic feel, not geometric.

```html
<svg width="100%" height="12" preserveAspectRatio="none" viewBox="0 0 400 12">
  <path d="M0 6 Q100 2, 200 6 Q300 10, 400 6" stroke="#f43f5e" stroke-width="0.5" fill="none" opacity="0.3"/>
</svg>
```

CSS: `.terminal-motto` - `font-style: italic; color: var(--terminal-dim); font-size: 0.625rem; font-family: var(--font-mono);`

### 1.3 Compact Navigation with Rosy SVGs

Extract current navigation (lines 10-105 in template) into a reusable function component `nav_bar/1` in `portfolio_live.ex`:

```elixir
attr :current_snapshot, :map, required: true
attr :has_prev, :boolean, required: true
attr :has_next, :boolean, required: true
attr :snapshot_position, :integer, required: true
attr :total_snapshots, :integer, required: true
attr :compact, :boolean, default: false
def nav_bar(assigns) do ... end
```

Compact version differences:
- Reduced vertical padding (py-1 vs py-2)
- Smaller button sizes (w-6 h-6 vs w-8 h-8)
- Smaller SVG icons (w-3 h-3 vs w-4 h-4)
- Thin rose SVG flourishes (~60px wide) flanking the date display
- No first/last buttons (only prev/next + date)

Rose flourish SVGs (before and after date):
```html
<svg width="60" height="8" viewBox="0 0 60 8">
  <path d="M0 4 Q15 1, 30 4 Q45 7, 60 4" stroke="#f43f5e" stroke-width="0.4" fill="none" opacity="0.35"/>
  <circle cx="30" cy="4" r="1" fill="#f43f5e" opacity="0.25"/>
</svg>
```

Place compact nav: (1) after brand+motto, (2) before chart, (3) after chart. Three instances total.

CSS: `.terminal-nav-bar-compact` - reduced height, tighter spacing

### 1.4 F&G Background Band in Main Chart

**File**: `lib/dividendsomatic_web/components/portfolio_chart.ex`

Currently F&G renders as a small progress bar at the SVG top (lines 246-258). Add a full-chart-area colored rectangle behind all data:

New function:
```elixir
defp svg_fear_greed_background(fear_greed, mt, main_h) do
  color = fg_color_hex(fear_greed.color)
  """
  <rect x="#{@ml}" y="#{mt}" width="#{@pw}" height="#{main_h}"
        fill="#{color}" opacity="0.06" rx="4"/>
  """
end
```

Insert in `render_combined/4` parts list between `svg_grid` and `svg_area_fill`:
```elixir
if(has_fg, do: svg_fear_greed_background(fear_greed, mt, main_h), else: ""),
```

Color meaning at a glance:
- Extreme Fear (0-25): Faint red tint → buying opportunity signal
- Fear (25-45): Faint orange tint
- Neutral (45-55): Faint yellow tint
- Greed (55-75): Faint emerald tint
- Extreme Greed (75-100): Faint green tint → caution signal

### 1.5 F&G Gauge in Holdings Section

The `render_fear_greed_gauge/1` function already exists (portfolio_chart.ex:437) but isn't called. Add to Holdings card header:

```heex
<div class="flex items-center justify-between mb-[var(--space-xs)]">
  <div class="terminal-section-label">Positions</div>
  <div class="flex items-center gap-[var(--space-sm)]">
    <%= if @fear_greed do %>
      {DividendsomaticWeb.Components.PortfolioChart.render_fear_greed_gauge(@fear_greed)}
    <% end %>
    <span class="terminal-holdings-count">{length(@holdings)} holdings</span>
  </div>
</div>
```

### 1.6 Enhanced Dividend Visualization

**File**: `portfolio_chart.ex`

Transform dividend display from bars to filled area chart with cumulative sum points.

Changes:
1. **New gradient** in `svg_defs/1`:
   ```xml
   <linearGradient id="div-area" x1="0" y1="0" x2="0" y2="1">
     <stop offset="0%" stop-color="#f59e0b" stop-opacity="0.20"/>
     <stop offset="100%" stop-color="#f59e0b" stop-opacity="0.03"/>
   </linearGradient>
   ```

2. **Replace bar rects** with area fill: In `svg_dividend_bars/5`, instead of individual `<rect>` elements, construct a filled `<path>` that creates an area chart from the bottom of the zone up to each monthly total.

3. **Area under cumulative line**: Add a filled path under the existing cumulative orange line in `svg_cumulative_line/4`. Create the area by extending the line path down to the baseline and closing.

4. **Keep dot markers**: The existing `<circle>` markers at each month point stay, with value labels.

### 1.7 Chart Animations ("Make it Live")

**Files**: `app.css`, `assets/js/app.js`, `portfolio_chart.ex`

1. **Path drawing animation** (CSS):
   ```css
   .combined-chart-container svg path[stroke="#10b981"] {
     animation: draw-line 1.2s ease-out forwards;
   }
   @keyframes draw-line {
     from { stroke-dashoffset: var(--path-length); }
     to { stroke-dashoffset: 0; }
   }
   ```

2. **Pulsing current-date marker** (CSS):
   ```css
   .chart-current-marker {
     animation: pulse-dot 2s ease-in-out infinite;
   }
   @keyframes pulse-dot {
     0%, 100% { opacity: 1; }
     50% { opacity: 0.6; filter: drop-shadow(0 0 4px #10b981); }
   }
   ```

3. **JS Hook `ChartAnimation`** in `app.js`:
   - On `updated()` callback, find SVG paths and trigger stroke-dashoffset animation
   - Uses `getTotalLength()` to calculate path length dynamically
   - Register in LiveSocket hooks

4. **Periodic F&G refresh** in `portfolio_live.ex`:
   ```elixir
   def handle_info(:refresh_fear_greed, socket) do
     fear_greed = get_fear_greed_data()
     Process.send_after(self(), :refresh_fear_greed, 30 * 60 * 1000)
     {:noreply, assign(socket, :fear_greed, fear_greed)}
   end
   ```

---

## Phase 2: PostgreSQL Migration (DONE)

### 2.1 Dependencies

**File**: `mix.exs`
- Remove: `{:ecto_sqlite3, "~> 0.22.0"}`
- Add: `{:postgrex, "~> 0.19"}`

### 2.2 Repo Adapter

**File**: `lib/dividendsomatic/repo.ex`
```elixir
# Change from:
adapter: Ecto.Adapters.SQLite3
# To:
adapter: Ecto.Adapters.Postgres
```

### 2.3 Config Updates

**config/dev.exs**:
```elixir
config :dividendsomatic, Dividendsomatic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dividendsomatic_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

**config/test.exs**:
```elixir
config :dividendsomatic, Dividendsomatic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dividendsomatic_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :dividendsomatic, Oban, testing: :inline
```

**config/runtime.exs**: Already uses `DATABASE_URL` for prod - verify no SQLite-specific options.

### 2.4 Fix SQLite SQL Fragments

**File**: `lib/dividendsomatic/portfolio.ex` (lines 349-354)

```elixir
# Replace 3 occurrences of:
fragment("strftime('%Y-%m', ?)", d.ex_date)
# With:
fragment("to_char(?, 'YYYY-MM')", d.ex_date)
```

### 2.5 Enable Oban

**File**: `lib/dividendsomatic/application.ex` (line 15)
- Uncomment: `{Oban, Application.fetch_env!(:dividendsomatic, Oban)}`

**File**: `config/test.exs` - Add: `config :dividendsomatic, Oban, testing: :inline`

### 2.6 Docker Compose

**New file**: `docker-compose.yml`
```yaml
services:
  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
volumes:
  pgdata:
```

### 2.7 Re-import Data

After migration: `mix ecto.reset` then batch import all 140+ CSVs from `csv_data/`. Add a `mix import.batch` task that globs `csv_data/*.csv` and imports each in date order.

---

## Phase 3: Generic Data Ingestion (DONE)

### IMPORTANT: CSV Fields Already Vary

**Proven fact**: The CSV format has already changed. Comparing oldest vs newest files:

```
July 4, 2025 (17 columns):
  ReportDate, CurrencyPrimary, Symbol, SubCategory, Quantity, MarkPrice,
  PositionValue, CostBasisPrice, CostBasisMoney, OpenPrice, PercentOfNAV,
  ListingExchange, AssetClass, FXRateToBase, ISIN, FIGI, HoldingPeriodDateTime

July 9, 2025+ (18 columns):
  ReportDate, CurrencyPrimary, Symbol, Description, SubCategory, Quantity,
  MarkPrice, PositionValue, CostBasisPrice, CostBasisMoney, OpenPrice,
  PercentOfNAV, FifoPnlUnrealized, ListingExchange, AssetClass, FXRateToBase,
  ISIN, FIGI
```

Changes: `Description` added, `FifoPnlUnrealized` added, `HoldingPeriodDateTime` removed.

**Current parser is positional** (`Portfolio.create_holding_from_row/2` maps by column index). This breaks when columns change. Must switch to **header-based parsing**.

### 3.0 Data Adaptability Architecture

The ingestion system must handle:

**Scenario A: IB Flex CSV with changing columns**
- Columns may be added, removed, or reordered between IB Flex report versions
- Solution: Parse by header name, not position. Unknown columns stored in metadata.

**Scenario B: Different IB report types**
- IB offers multiple report formats (Flex, Statement, Activity)
- Solution: Each format gets its own normalizer that maps to canonical schema.

**Scenario C: IBKR Client Portal API (future)**
- JSON responses instead of CSV
- Different field names (e.g., `mktPrice` instead of `MarkPrice`)
- Solution: API adapter with its own normalizer mapping JSON fields to canonical.

**Scenario D: Other brokers entirely**
- Nordnet, Degiro, Saxo, etc. each have unique export formats
- Solution: Broker-specific normalizers that all output the same canonical format.

**Scenario E: Enrichment from multiple sources**
- Base data from broker CSV + dividend data from EODHD + real-time from Finnhub
- Solution: Canonical schema has nullable fields. Different sources fill what they can. Later sources can enrich existing records.

### 3.1 Canonical Holding Format

Define a standard internal format that all sources normalize to:

```elixir
# All fields optional except report_date and symbol
%{
  # Required (identity)
  report_date: ~D[2026-02-09],
  symbol: "KESKOB",

  # Common fields (may be nil if source doesn't provide)
  description: "KESKO OYJ-B SHS",
  currency_primary: "EUR",
  quantity: Decimal.new("2000"),
  mark_price: Decimal.new("20.96"),
  position_value: Decimal.new("41920"),
  cost_basis_price: Decimal.new("19.53"),
  cost_basis_money: Decimal.new("39060.18"),
  fifo_pnl_unrealized: Decimal.new("2859.82"),
  percent_of_nav: Decimal.new("13.41"),
  listing_exchange: "HEX",
  asset_class: "STK",
  isin: "FI0009000202",
  figi: "BBG000BNP2B2",

  # Metadata (source-specific extra fields preserved as JSON)
  source: "ib_flex_csv",
  source_metadata: %{"HoldingPeriodDateTime" => "2024-06-15", ...}
}
```

### 3.2 DataIngestion Context + Behaviour

**New file**: `lib/dividendsomatic/data_ingestion.ex`

```elixir
defmodule Dividendsomatic.DataIngestion do
  @moduledoc """
  Generic data ingestion for portfolio data from any source.
  Each source implements the Source behaviour.
  Each format implements the Normalizer behaviour.
  """

  # Source: where data comes from (directory, email, API)
  @callback list_available(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_data(source_ref :: term()) :: {:ok, binary()} | {:error, term()}
  @callback source_name() :: String.t()

  def import_new_from_source(adapter, normalizer, opts \\ []) do
    # 1. List available data from source
    # 2. Filter already-imported dates
    # 3. Fetch raw data
    # 4. Normalize to canonical format
    # 5. Import via Portfolio context
  end
end
```

### 3.3 Normalizer Behaviour

**New file**: `lib/dividendsomatic/data_ingestion/normalizer.ex`

```elixir
defmodule Dividendsomatic.DataIngestion.Normalizer do
  @moduledoc """
  Behaviour for normalizing raw data into canonical holding format.
  Each data format (IB Flex CSV, IBKR API JSON, Nordnet CSV, etc.)
  implements this to map its fields to the canonical schema.
  """

  @callback detect?(binary()) :: boolean()  # Can this normalizer handle this data?
  @callback normalize(binary()) :: {:ok, %{date: Date.t(), holdings: [map()]}} | {:error, term()}
end
```

### 3.4 IB Flex CSV Normalizer

**New file**: `lib/dividendsomatic/data_ingestion/normalizers/ib_flex_csv.ex`

**Key design: header-based parsing**, not positional:

```elixir
defmodule Dividendsomatic.DataIngestion.Normalizers.IbFlexCsv do
  @behaviour Dividendsomatic.DataIngestion.Normalizer

  # Known field mappings (CSV header → canonical field)
  @field_map %{
    "ReportDate" => :report_date,
    "CurrencyPrimary" => :currency_primary,
    "Symbol" => :symbol,
    "Description" => :description,
    "SubCategory" => :sub_category,
    "Quantity" => :quantity,
    "MarkPrice" => :mark_price,
    "PositionValue" => :position_value,
    "CostBasisPrice" => :cost_basis_price,
    "CostBasisMoney" => :cost_basis_money,
    "OpenPrice" => :open_price,
    "PercentOfNAV" => :percent_of_nav,
    "FifoPnlUnrealized" => :fifo_pnl_unrealized,
    "ListingExchange" => :listing_exchange,
    "AssetClass" => :asset_class,
    "FXRateToBase" => :fx_rate_to_base,
    "ISIN" => :isin,
    "FIGI" => :figi
  }

  def detect?(data), do: String.contains?(data, "ReportDate") and String.contains?(data, "Symbol")

  def normalize(csv_data) do
    # 1. Parse header row to get column names
    # 2. Map each data row using header names (not positions)
    # 3. Known fields → canonical schema fields
    # 4. Unknown fields → source_metadata map
    # 5. Return {:ok, %{date: date, holdings: [canonical_maps]}}
  end
end
```

This handles ALL historical CSV variations automatically because it maps by header name.

### 3.5 Future Normalizer Examples

**IBKR Client Portal API** (Scenario C):
```elixir
defmodule Dividendsomatic.DataIngestion.Normalizers.IbkrApi do
  @field_map %{
    "conid" => :conid,
    "ticker" => :symbol,
    "name" => :description,
    "mktPrice" => :mark_price,
    "mktValue" => :position_value,
    "avgCost" => :cost_basis_price,
    "position" => :quantity,
    "unrealizedPnl" => :fifo_pnl_unrealized,
    "currency" => :currency_primary
  }
end
```

**Nordnet CSV export** (Scenario D):
```elixir
defmodule Dividendsomatic.DataIngestion.Normalizers.NordnetCsv do
  @field_map %{
    "Instrumentnamn" => :description,   # Swedish field names
    "ISIN" => :isin,
    "Antal" => :quantity,
    "Senaste" => :mark_price,
    "Värde" => :position_value,
    "Anskaffningsvärde" => :cost_basis_money
  }
end
```

### 3.6 Auto-Detection

The import pipeline auto-detects format:

```elixir
def detect_normalizer(raw_data) do
  normalizers = [
    Normalizers.IbFlexCsv,
    Normalizers.IbkrApi,
    Normalizers.NordnetCsv
    # Add new normalizers here
  ]

  Enum.find(normalizers, fn mod -> mod.detect?(raw_data) end)
end
```

### 3.7 Source Adapters

**CSV Directory** (`lib/dividendsomatic/data_ingestion/sources/csv_directory.ex`):
- Lists `.csv` files in configured directory
- Extracts dates from filenames (IB pattern: `flex.ACCOUNT.PortfolioForWww.YYYYMMDD.YYYYMMDD.csv`)
- Also handles generic filenames by parsing CSV headers for ReportDate

**Gmail** (`lib/dividendsomatic/data_ingestion/sources/gmail_adapter.ex`):
- Wraps existing `Dividendsomatic.Gmail` behind Source behaviour

**IBKR API** (future) (`lib/dividendsomatic/data_ingestion/sources/ibkr_api.ex`):
- REST API calls to IBKR Client Portal
- Returns JSON instead of CSV

### 3.8 Schema Changes for Metadata

**Migration**: Add `source` and `source_metadata` fields to `holdings` table:
```elixir
alter table(:holdings) do
  add :source, :string            # "ib_flex_csv", "ibkr_api", "nordnet", etc.
  add :source_metadata, :map      # JSON blob for extra fields from source
end
```

Also add `source_metadata` to `portfolio_snapshots`:
```elixir
alter table(:portfolio_snapshots) do
  add :import_source, :string     # Which adapter imported this snapshot
end
```

### 3.9 DataImportWorker

**New file**: `lib/dividendsomatic/workers/data_import_worker.ex`

```elixir
defmodule Dividendsomatic.Workers.DataImportWorker do
  use Oban.Worker, queue: :data_import, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => source_type}}) do
    adapter = resolve_adapter(source_type)
    Dividendsomatic.DataIngestion.import_new_from_source(adapter)
    # Normalizer auto-detected from data content
  end

  defp resolve_adapter("csv_directory"), do: Sources.CsvDirectory
  defp resolve_adapter("gmail"), do: Sources.GmailAdapter
  defp resolve_adapter("ibkr_api"), do: Sources.IbkrApi
end
```

### 3.10 Oban Cron Update

**File**: `config/config.exs`

```elixir
config :dividendsomatic, Oban,
  repo: Dividendsomatic.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 12 * * 1-5", Dividendsomatic.Workers.DataImportWorker, args: %{"source" => "csv_directory"}}
     ]}
  ],
  queues: [default: 10, data_import: 1]
```

### 3.11 Scenario Summary

| Scenario | Source Adapter | Normalizer | Status |
|----------|--------------|------------|--------|
| IB Flex CSV (current) | CsvDirectory | IbFlexCsv | Build now |
| IB Flex via Gmail | GmailAdapter | IbFlexCsv | Build now (wraps existing) |
| IB Flex CSV (old format) | CsvDirectory | IbFlexCsv | Works automatically (header-based) |
| IB Flex CSV (future fields) | CsvDirectory | IbFlexCsv | Works automatically (unknown → metadata) |
| IBKR Client Portal API | IbkrApi | IbkrApi | Future |
| Nordnet CSV export | CsvDirectory | NordnetCsv | Future |
| Degiro CSV export | CsvDirectory | DegiroCsv | Future |
| Manual JSON upload | FileUpload | Auto-detect | Future |

---

## Phase 4: Stock Detail Pages (DONE)

### 4.1 Route

**File**: `lib/dividendsomatic_web/router.ex`

```elixir
live "/stocks/:symbol", StockLive, :show
```

### 4.2 StockLive

**New files**: `lib/dividendsomatic_web/live/stock_live.ex` + `stock_live.html.heex`

Page sections:
- **Header**: Symbol, company name, logo (from CompanyProfile)
- **Quote card**: Current price, change, %, high/low, open, prev close (from StockQuote)
- **Company info**: Sector, industry, country, exchange, IPO date, market cap, website link
- **Holdings history**: Line chart of shares owned over time (query from snapshots by symbol)
- **Dividend history**: Table of all dividends for this symbol
- **External links**: Yahoo Finance, SeekingAlpha, Nordnet (context-dependent)

### 4.3 External Links

Link patterns by exchange:

| Exchange | Yahoo Finance | SeekingAlpha | Nordnet |
|----------|--------------|--------------|---------|
| HEX (Helsinki) | `yahoo.com/quote/{SYMBOL}.HE` | - | `nordnet.fi/markkina/osakkeet/{ISIN}` |
| NYSE | `yahoo.com/quote/{SYMBOL}` | `seekingalpha.com/symbol/{SYMBOL}` | - |
| NASDAQ | `yahoo.com/quote/{SYMBOL}` | `seekingalpha.com/symbol/{SYMBOL}` | - |
| TSE (Tokyo) | `yahoo.com/quote/{SYMBOL}.T` | - | - |
| HKEX | `yahoo.com/quote/{SYMBOL}.HK` | - | - |

### 4.4 Clickable Symbols

**File**: `portfolio_live.html.heex` (line 288)

```heex
<td>
  <.link navigate={~p"/stocks/#{holding.symbol}"} class="terminal-symbol hover:underline">
    {holding.symbol}
  </.link>
</td>
```

---

## Phase 5: Market Data Research (DONE)

See separate file: `docs/MARKET_DATA_RESEARCH.md`

---

## GitHub Issues

All issues closed except #22:

| # | Title | Phase | Status |
|---|-------|-------|--------|
| 12 | Template restructure: dual compact nav | 1.1, 1.3 | Closed |
| 13 | Brand area: tagline + decorative rose SVG line | 1.2 | Closed |
| 14 | F&G chart background band + gauge in holdings header | 1.4, 1.5 | Closed |
| 15 | Enhanced dividend visualization: filled area chart | 1.6 | Closed |
| 16 | Chart animations: path drawing, pulsing marker, live feel | 1.7 | Closed |
| 17 | PostgreSQL migration + docker-compose + enable Oban | 2.1-2.6 | Closed |
| 18 | Batch CSV re-import after PostgreSQL migration | 2.7 | Closed |
| 19 | Generic data ingestion module with CSV directory adapter | 3.1-3.6 | Closed |
| 20 | Stock detail pages with external links | 4.1-4.4 | Closed |
| 21 | Market data provider research document | 5.1 | Closed |
| **22** | **Multi-provider market data architecture** | **5** | **Open** |

---

## Execution Summary

All phases completed 2026-02-10:
1. **Phase 1** - UI overhaul (#12-16)
2. **Phase 2** - PostgreSQL migration (#17)
3. **Phase 3** - Data ingestion (#18-19)
4. **Phase 4** - Stock detail pages (#20)
5. **Phase 5** - Market data research (#21)

**Remaining:** #22 Multi-provider market data architecture (future work)

---

## Verification

After each phase:
- `mix test` - all 125+ tests pass (update tests for new features)
- `mix format && mix credo --strict` - no new issues
- Visual check at `localhost:4000`
- Phase 2: `mix ecto.reset` + batch re-import CSVs

---

## Critical Files

| File | Changes |
|------|---------|
| `lib/dividendsomatic_web/live/portfolio_live.html.heex` | Template restructure, nav components, F&G gauge, clickable symbols |
| `lib/dividendsomatic_web/live/portfolio_live.ex` | Nav component, tagline, F&G refresh timer |
| `lib/dividendsomatic_web/components/portfolio_chart.ex` | F&G background, dividend area chart, animation hooks |
| `assets/css/app.css` | Compact nav, decorative SVGs, tagline, animations |
| `assets/js/app.js` | ChartAnimation JS hook |
| `lib/dividendsomatic/repo.ex` | SQLite3 → Postgres adapter |
| `lib/dividendsomatic/portfolio.ex` | strftime → to_char fragments |
| `lib/dividendsomatic/application.ex` | Enable Oban |
| `mix.exs` | ecto_sqlite3 → postgrex |
| `config/dev.exs`, `config/test.exs`, `config/config.exs` | PostgreSQL + Oban config |
| `docker-compose.yml` | New: PostgreSQL container |
| `lib/dividendsomatic/data_ingestion.ex` | New: generic ingestion context |
| `lib/dividendsomatic/data_ingestion/*.ex` | New: adapters + normalizer |
| `lib/dividendsomatic/workers/data_import_worker.ex` | New: generic import worker |
| `lib/dividendsomatic_web/live/stock_live.ex` | New: stock detail page |
| `lib/dividendsomatic_web/router.ex` | New route: /stocks/:symbol |
| `docs/MARKET_DATA_RESEARCH.md` | New: API research document |
