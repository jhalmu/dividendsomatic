defmodule Dividendsomatic.Repo.Migrations.CreateCleanTables do
  use Ecto.Migration

  def change do
    # 1. instruments — Master Instrument Registry
    create table(:instruments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :isin, :string, null: false
      add :cusip, :string
      add :conid, :integer
      add :figi, :string
      add :name, :string
      add :asset_category, :string
      add :listing_exchange, :string
      add :currency, :string
      add :multiplier, :decimal, default: 1
      add :type, :string
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:instruments, [:isin])
    create index(:instruments, [:conid])
    create index(:instruments, [:currency])

    # 2. instrument_aliases — Symbol History
    create table(:instrument_aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :instrument_id, references(:instruments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :symbol, :string, null: false
      add :exchange, :string
      add :valid_from, :date
      add :valid_to, :date
      add :source, :string

      timestamps()
    end

    create index(:instrument_aliases, [:instrument_id])
    create index(:instrument_aliases, [:symbol])
    create unique_index(:instrument_aliases, [:instrument_id, :symbol, :exchange])

    # 3. trades — Clean Trade Records
    create table(:trades, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false

      add :instrument_id, references(:instruments, type: :binary_id, on_delete: :restrict),
        null: false

      add :trade_date, :date, null: false
      add :trade_time, :time
      add :settlement_date, :date
      add :quantity, :decimal, null: false
      add :price, :decimal, null: false
      add :amount, :decimal, null: false
      add :commission, :decimal, default: 0
      add :currency, :string, null: false
      add :fx_rate, :decimal
      add :asset_category, :string
      add :exchange, :string
      add :description, :string
      add :raw_data, :map, default: %{}

      timestamps()
    end

    create unique_index(:trades, [:external_id])
    create index(:trades, [:instrument_id])
    create index(:trades, [:trade_date])

    # 4. dividend_payments — Dividends + Withholding Tax Paired
    create table(:dividend_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false

      add :instrument_id, references(:instruments, type: :binary_id, on_delete: :restrict),
        null: false

      add :ex_date, :date
      add :pay_date, :date, null: false
      add :gross_amount, :decimal, null: false
      add :withholding_tax, :decimal, default: 0
      add :net_amount, :decimal, null: false
      add :currency, :string, null: false
      add :fx_rate, :decimal
      add :amount_eur, :decimal
      add :quantity, :decimal
      add :per_share, :decimal
      add :description, :string
      add :raw_data, :map, default: %{}

      timestamps()
    end

    create unique_index(:dividend_payments, [:external_id])
    create index(:dividend_payments, [:instrument_id])
    create index(:dividend_payments, [:pay_date])

    # 5. cash_flows — Deposits, Withdrawals, Interest, Fees
    create table(:cash_flows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :flow_type, :string, null: false
      add :date, :date, null: false
      add :amount, :decimal, null: false
      add :currency, :string, null: false
      add :fx_rate, :decimal
      add :amount_eur, :decimal
      add :description, :string
      add :raw_data, :map, default: %{}

      timestamps()
    end

    create unique_index(:cash_flows, [:external_id])
    create index(:cash_flows, [:flow_type])
    create index(:cash_flows, [:date])

    # 6. corporate_actions — Splits, Mergers, Symbol Changes
    create table(:corporate_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instrument_id, references(:instruments, type: :binary_id, on_delete: :restrict)
      add :action_type, :string, null: false
      add :date, :date, null: false
      add :description, :string
      add :quantity, :decimal
      add :amount, :decimal
      add :raw_data, :map, default: %{}

      timestamps()
    end

    create index(:corporate_actions, [:instrument_id])
    create index(:corporate_actions, [:date])
  end
end
