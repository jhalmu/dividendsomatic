defmodule Dividendsomatic.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # positions.symbol — used in dashboard position lookups
    create_if_not_exists index(:positions, [:symbol], concurrently: true)

    # dividend_payments.ex_date — used in dividend timeline queries
    create_if_not_exists index(:dividend_payments, [:ex_date], concurrently: true)

    # dividend_payments(instrument_id, pay_date) — compound for per-instrument dividend lookups
    create_if_not_exists index(:dividend_payments, [:instrument_id, :pay_date],
                           concurrently: true
                         )

    # cash_flows(flow_type, date) — compound for filtered cash flow queries
    create_if_not_exists index(:cash_flows, [:flow_type, :date], concurrently: true)

    # trades(instrument_id, trade_date) — compound for per-instrument trade history
    create_if_not_exists index(:trades, [:instrument_id, :trade_date], concurrently: true)

    # instruments.figi — used in symbol resolution fallback
    create_if_not_exists index(:instruments, [:figi], concurrently: true)
  end
end
