# API Reference

## Portfolio Context

Main context for portfolio operations.

**Module:** `Dividendsomatic.Portfolio`

### Functions

#### get_latest_snapshot/0

Returns the most recent portfolio snapshot with preloaded holdings.

```elixir
Portfolio.get_latest_snapshot()
# => %PortfolioSnapshot{report_date: ~D[2026-01-28], holdings: [...]}
# => nil (if no snapshots exist)
```

---

#### get_snapshot_by_date/1

Returns snapshot for a specific date.

**Parameters:**
- `date` - Date (Date struct or string "YYYY-MM-DD")

```elixir
Portfolio.get_snapshot_by_date(~D[2026-01-28])
# => %PortfolioSnapshot{...}
# => nil (if not found)
```

---

#### get_previous_snapshot/1

Returns the snapshot before the given date.

**Parameters:**
- `date` - Date to search before

```elixir
Portfolio.get_previous_snapshot(~D[2026-01-28])
# => %PortfolioSnapshot{report_date: ~D[2026-01-27], ...}
# => nil (if no earlier snapshot)
```

**Used for:** Left arrow navigation (←)

---

#### get_next_snapshot/1

Returns the snapshot after the given date.

**Parameters:**
- `date` - Date to search after

```elixir
Portfolio.get_next_snapshot(~D[2026-01-28])
# => %PortfolioSnapshot{report_date: ~D[2026-01-29], ...}
# => nil (if no later snapshot)
```

**Used for:** Right arrow navigation (→)

---

#### list_snapshots/0

Returns all snapshots ordered by date (newest first).

```elixir
Portfolio.list_snapshots()
# => [%PortfolioSnapshot{}, %PortfolioSnapshot{}, ...]
```

---

#### create_snapshot_from_csv/2

Creates a new portfolio snapshot from CSV data.

**Parameters:**
- `csv_data` - String containing CSV data
- `report_date` - Date struct for the snapshot

**Returns:**
- `{:ok, {:ok, snapshot}}` - Success
- `{:error, changeset}` - Validation failed

```elixir
csv_data = File.read!("flex.csv")
report_date = ~D[2026-01-28]

Portfolio.create_snapshot_from_csv(csv_data, report_date)
# => {:ok, {:ok, %PortfolioSnapshot{...}}}
```

**Transaction:** Creates snapshot + all holdings in a single transaction.

---

## Schemas

### PortfolioSnapshot

Represents a daily portfolio snapshot.

**Table:** `portfolio_snapshots`

**Fields:**
- `id` - UUID (binary_id)
- `report_date` - Date (unique)
- `raw_csv_data` - Text (backup of CSV)
- `inserted_at` - DateTime
- `updated_at` - DateTime

**Associations:**
- `has_many :holdings` - Related holdings

**Example:**
```elixir
%PortfolioSnapshot{
  id: "7bda6c38-6616-4168-a873-5c439efc1a3f",
  report_date: ~D[2026-01-28],
  holdings: [%Holding{}, ...],
  inserted_at: ~N[2026-01-29 21:09:16],
  updated_at: ~N[2026-01-29 21:09:16]
}
```

---

### Holding

Represents a single portfolio position.

**Table:** `holdings`

**Fields:**
- `id` - UUID (binary_id)
- `portfolio_snapshot_id` - Foreign key to snapshot
- `report_date` - Date
- `currency_primary` - String (EUR, USD, etc.)
- `symbol` - String (KESKOB, AAPL, etc.)
- `description` - String (company name)
- `sub_category` - String (COMMON, REIT, etc.)
- `quantity` - Decimal
- `mark_price` - Decimal (current price)
- `position_value` - Decimal (quantity × price)
- `cost_basis_price` - Decimal (purchase price)
- `cost_basis_money` - Decimal (total cost)
- `open_price` - Decimal
- `percent_of_nav` - Decimal (% of total portfolio)
- `fifo_pnl_unrealized` - Decimal (unrealized profit/loss)
- `listing_exchange` - String (NYSE, NASDAQ, HEX, etc.)
- `asset_class` - String (STK = stock)
- `fx_rate_to_base` - Decimal (currency conversion rate)
- `isin` - String (international security ID)
- `figi` - String (financial instrument global ID)
- `inserted_at` - DateTime
- `updated_at` - DateTime

**Associations:**
- `belongs_to :portfolio_snapshot` - Parent snapshot

**Example:**
```elixir
%Holding{
  id: "4eb517d4-ecbe-4864-a3c5-d68d0157ba27",
  symbol: "KESKOB",
  description: "KESKO OYJ-B SHS",
  quantity: Decimal.new("1000"),
  mark_price: Decimal.new("21"),
  position_value: Decimal.new("21000"),
  cost_basis_money: Decimal.new("18264.59"),
  fifo_pnl_unrealized: Decimal.new("2735.41"),
  percent_of_nav: Decimal.new("8.90"),
  currency_primary: "EUR",
  ...
}
```

---

## LiveView

### PortfolioLive

Main portfolio viewer interface.

**Module:** `DividendsomaticWeb.PortfolioLive`

**Routes:**
- `GET /` - Latest snapshot
- `GET /portfolio/:date` - Specific date

**Assigns:**
- `@snapshot` - Current PortfolioSnapshot (with preloaded holdings)
- `@loading` - Boolean loading state

**Events:**
- `navigate` (direction: "prev" | "next") - Navigate between dates

**Keyboard:**
- `ArrowLeft` - Previous snapshot
- `ArrowRight` - Next snapshot

---

## Mix Tasks

### import.csv

Import CSV file into database.

```bash
mix import.csv path/to/file.csv
```

**Module:** `Mix.Tasks.Import.Csv`

**Steps:**
1. Read CSV file
2. Extract report date from first data row
3. Create snapshot with all holdings
4. Display success/error message

**Output:**
```
Importing snapshot for 2026-01-28...
✓ Successfully imported 7 holdings
```

---

## Database Schema

### portfolio_snapshots

```sql
CREATE TABLE portfolio_snapshots (
  id UUID PRIMARY KEY,
  report_date DATE NOT NULL UNIQUE,
  raw_csv_data TEXT,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX ON portfolio_snapshots(report_date);
```

### holdings

```sql
CREATE TABLE holdings (
  id UUID PRIMARY KEY,
  portfolio_snapshot_id UUID NOT NULL REFERENCES portfolio_snapshots ON DELETE CASCADE,
  report_date DATE NOT NULL,
  currency_primary VARCHAR,
  symbol VARCHAR NOT NULL,
  description VARCHAR,
  sub_category VARCHAR,
  quantity DECIMAL,
  mark_price DECIMAL,
  position_value DECIMAL,
  cost_basis_price DECIMAL,
  cost_basis_money DECIMAL,
  open_price DECIMAL,
  percent_of_nav DECIMAL,
  fifo_pnl_unrealized DECIMAL,
  listing_exchange VARCHAR,
  asset_class VARCHAR,
  fx_rate_to_base DECIMAL,
  isin VARCHAR,
  figi VARCHAR,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX ON holdings(portfolio_snapshot_id);
CREATE INDEX ON holdings(symbol);
CREATE INDEX ON holdings(report_date);
```

---

## CSV Format

Interactive Brokers "Activity Flex" CSV format:

```csv
ReportDate,CurrencyPrimary,Symbol,Description,SubCategory,Quantity,MarkPrice,PositionValue,CostBasisPrice,CostBasisMoney,OpenPrice,PercentOfNAV,FifoPnlUnrealized,ListingExchange,AssetClass,FXRateToBase,ISIN,FIGI
2026-01-28,EUR,KESKOB,KESKO OYJ-B SHS,COMMON,1000,21,21000,18.26459,18264.59,18.26459,8.90,2735.41,HEX,STK,1,FI0009000202,BBG000BNP2B2
```

**Fields (18 total):**
1. ReportDate - YYYY-MM-DD
2. CurrencyPrimary - EUR, USD, etc.
3. Symbol - Ticker symbol
4. Description - Company name
5. SubCategory - COMMON, REIT, etc.
6. Quantity - Number of shares
7. MarkPrice - Current market price
8. PositionValue - Total value
9. CostBasisPrice - Purchase price per share
10. CostBasisMoney - Total cost basis
11. OpenPrice - Opening price
12. PercentOfNAV - % of portfolio
13. FifoPnlUnrealized - Unrealized P&L
14. ListingExchange - Exchange code
15. AssetClass - STK, OPT, etc.
16. FXRateToBase - Currency conversion rate
17. ISIN - International ID
18. FIGI - Global ID

---

## Error Handling

All context functions return structured results:

**Success:**
```elixir
{:ok, result}
```

**Error:**
```elixir
{:error, changeset}
{:error, reason}
```

**Example:**
```elixir
case Portfolio.create_snapshot_from_csv(csv, date) do
  {:ok, {:ok, snapshot}} ->
    # Success
  {:error, changeset} ->
    # Validation failed
end
```

---

## Decimal Handling

All money/quantity fields use `Decimal` type for precision.

**Usage:**
```elixir
# Create
Decimal.new("100.50")

# Math
Decimal.add(a, b)
Decimal.mult(a, b)

# Compare
Decimal.negative?(value)
Decimal.compare(a, b)

# Convert
Decimal.to_float(value)
Decimal.to_string(value, :normal)
```

---

## Configuration

**Database:** `config/dev.exs`, `config/prod.exs`
```elixir
config :dividendsomatic, Dividendsomatic.Repo,
  database: "dividendsomatic_dev.db"
```

**Endpoint:** `config/config.exs`
```elixir
config :dividendsomatic, DividendsomaticWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [...]
```

---

## Testing Helpers

**Factory (to be implemented):**
```elixir
# test/support/factory.ex
def portfolio_snapshot_factory do
  %PortfolioSnapshot{
    report_date: Date.utc_today(),
    raw_csv_data: "..."
  }
end
```

**Test usage:**
```elixir
snapshot = insert(:portfolio_snapshot)
holding = insert(:holding, portfolio_snapshot: snapshot)
```
