# Development Guide

## Project Structure

```
dividendsomatic/
├── lib/
│   ├── dividendsomatic/           # Business logic
│   │   ├── portfolio.ex           # Main context
│   │   └── portfolio/             # Domain schemas
│   │
│   └── dividendsomatic_web/       # Web interface
│       ├── live/                  # LiveView modules
│       ├── components/            # Reusable components
│       └── router.ex              # Routes
│
├── priv/
│   └── repo/
│       ├── migrations/            # Database migrations
│       └── seeds.exs              # Seed data
│
├── test/                          # Test files
├── config/                        # Configuration
└── assets/                        # CSS, JS assets
```

## Key Patterns

### Context Pattern

All database operations go through contexts:

```elixir
# Good ✅
Portfolio.get_latest_snapshot()
Portfolio.create_snapshot_from_csv(csv_data, date)

# Bad ❌
Repo.get(PortfolioSnapshot, id)  # Don't access Repo directly
```

### Schema Pattern

Schemas define database tables:

```elixir
defmodule Dividendsomatic.Portfolio.PortfolioSnapshot do
  use Ecto.Schema
  
  schema "portfolio_snapshots" do
    field :report_date, :date
    has_many :holdings, Holding
    timestamps()
  end
end
```

### LiveView Pattern

LiveView for interactive UIs:

```elixir
defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view
  
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :data, load_data())}
  end
  
  def handle_event("action", _params, socket) do
    {:noreply, socket}
  end
end
```

## Design System

### DaisyUI Components

Use DaisyUI classes:

```heex
<!-- Card -->
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Title</h2>
    <p>Content</p>
  </div>
</div>

<!-- Button -->
<button class="btn btn-primary">Click</button>

<!-- Table -->
<table class="table table-zebra">
  <thead><tr><th>Header</th></tr></thead>
  <tbody><tr><td>Data</td></tr></tbody>
</table>
```

### Design Tokens

Use CSS variables from homesite:

```css
/* Spacing */
gap-[var(--space-sm)]    /* 8-16px */
gap-[var(--space-md)]    /* 16-32px */
gap-[var(--space-lg)]    /* 32-64px */

/* Typography */
text-[var(--text-base)]  /* 16-20px */
text-[var(--text-lg)]    /* 18-24px */
text-[var(--text-2xl)]   /* 24-32px */

/* Padding */
p-[var(--space-sm)]
p-[var(--space-md)]
```

## Database

### Creating Migrations

```bash
mix ecto.gen.migration create_table_name
```

Edit the generated file:

```elixir
defmodule Dividendsomatic.Repo.Migrations.CreateTableName do
  use Ecto.Migration

  def change do
    create table(:table_name, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :field_name, :string
      timestamps()
    end
    
    create index(:table_name, [:field_name])
  end
end
```

Run migration:
```bash
mix ecto.migrate
```

### Adding Schema

Create schema file:

```elixir
defmodule Dividendsomatic.Schema.ModelName do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "table_name" do
    field :field_name, :string
    timestamps()
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [:field_name])
    |> validate_required([:field_name])
  end
end
```

## Testing

### Context Tests

```elixir
defmodule Dividendsomatic.PortfolioTest do
  use Dividendsomatic.DataCase
  alias Dividendsomatic.Portfolio

  describe "get_latest_snapshot/0" do
    test "returns the most recent snapshot" do
      # Setup
      snapshot = insert(:portfolio_snapshot)
      
      # Test
      result = Portfolio.get_latest_snapshot()
      
      # Assert
      assert result.id == snapshot.id
    end
  end
end
```

### LiveView Tests

```elixir
defmodule DividendsomaticWeb.PortfolioLiveTest do
  use DividendsomaticWeb.ConnCase
  import Phoenix.LiveViewTest

  test "displays portfolio", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Portfolio Snapshot"
  end
  
  test "navigates with arrow keys", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    
    view
    |> element("button", "Next")
    |> render_click()
    
    assert_patch(view, "/portfolio/2026-01-29")
  end
end
```

## Adding Features

### 1. Create Migration

```bash
mix ecto.gen.migration add_feature
```

### 2. Create Schema

```elixir
# lib/dividendsomatic/domain/schema_name.ex
defmodule Dividendsomatic.Domain.SchemaName do
  use Ecto.Schema
  # ... schema definition
end
```

### 3. Update Context

```elixir
# lib/dividendsomatic/domain.ex
defmodule Dividendsomatic.Domain do
  # Add functions
  def create_thing(attrs) do
    %SchemaName{}
    |> SchemaName.changeset(attrs)
    |> Repo.insert()
  end
end
```

### 4. Create LiveView

```elixir
# lib/dividendsomatic_web/live/feature_live.ex
defmodule DividendsomaticWeb.FeatureLive do
  use DividendsomaticWeb, :live_view
  
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :items, load_items())}
  end
  
  def render(assigns) do
    ~H"""
    <div>
      <!-- UI code -->
    </div>
    """
  end
end
```

### 5. Add Route

```elixir
# lib/dividendsomatic_web/router.ex
scope "/", DividendsomaticWeb do
  pipe_through :browser
  live "/feature", FeatureLive
end
```

### 6. Write Tests

```elixir
# test/dividendsomatic/domain_test.exs
# test/dividendsomatic_web/live/feature_live_test.exs
```

## Common Tasks

### Add New CSV Field

1. Create migration:
```bash
mix ecto.gen.migration add_field_to_holdings
```

2. Edit migration:
```elixir
def change do
  alter table(:holdings) do
    add :new_field, :string
  end
end
```

3. Update schema:
```elixir
# lib/dividendsomatic/portfolio/holding.ex
schema "holdings" do
  field :new_field, :string
  # ...
end
```

4. Update CSV parser:
```elixir
# lib/dividendsomatic/portfolio.ex
defp create_holding_from_row(row, snapshot_id) do
  attrs = %{
    new_field: Enum.at(row, 18),  # New column index
    # ...
  }
end
```

5. Update LiveView:
```heex
<td><%= holding.new_field %></td>
```

### Add Background Job

1. Create worker:
```elixir
# lib/dividendsomatic/workers/job_worker.ex
defmodule Dividendsomatic.Workers.JobWorker do
  use Oban.Worker
  
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Job logic
    :ok
  end
end
```

2. Schedule in config:
```elixir
# config/config.exs
config :dividendsomatic, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 6 * * *", Dividendsomatic.Workers.JobWorker}
     ]}
  ]
```

## Debugging

### IEx.pry

Add breakpoint:
```elixir
require IEx
IEx.pry()
```

### Logger

```elixir
require Logger
Logger.info("Debug info: #{inspect(data)}")
```

### Database Queries

```elixir
# See SQL queries
config :dividendsomatic, Dividendsomatic.Repo,
  log: :info
```

## Performance

### Query Optimization

Use `preload` to avoid N+1:
```elixir
# Good ✅
Repo.all(PortfolioSnapshot)
|> Repo.preload(:holdings)

# Bad ❌
snapshots = Repo.all(PortfolioSnapshot)
Enum.map(snapshots, & &1.holdings)  # N+1 queries
```

### Indexes

Add indexes for frequently queried fields:
```elixir
create index(:table, [:field])
create unique_index(:table, [:field])
```

## Code Style

### Formatting

```bash
mix format
```

### Credo

```bash
mix credo
mix credo --strict
```

### Naming

- Contexts: Nouns (Portfolio, Dividend)
- Functions: Verbs (get_, create_, update_)
- Schemas: Singular (PortfolioSnapshot, Holding)
- Tables: Plural (portfolio_snapshots, holdings)

## Resources

- Phoenix: https://hexdocs.pm/phoenix
- LiveView: https://hexdocs.pm/phoenix_live_view
- Ecto: https://hexdocs.pm/ecto
- DaisyUI: https://daisyui.com
