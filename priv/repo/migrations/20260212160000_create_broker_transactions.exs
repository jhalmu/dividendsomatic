defmodule Dividendsomatic.Repo.Migrations.CreateBrokerTransactions do
  use Ecto.Migration

  def change do
    create table(:broker_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string
      add :broker, :string, null: false
      add :transaction_type, :string, null: false
      add :raw_type, :string, null: false
      add :entry_date, :date
      add :trade_date, :date
      add :settlement_date, :date
      add :portfolio_id, :string
      add :security_name, :string
      add :isin, :string
      add :quantity, :decimal
      add :price, :decimal
      add :amount, :decimal
      add :interest, :decimal
      add :total_costs, :decimal
      add :commission, :decimal
      add :currency, :string
      add :acquisition_value, :decimal
      add :result, :decimal
      add :total_quantity, :decimal
      add :balance, :decimal
      add :exchange_rate, :decimal
      add :reference_fx_rate, :decimal
      add :description, :string
      add :confirmation_number, :string
      add :raw_data, :map

      timestamps()
    end

    create index(:broker_transactions, [:broker])
    create index(:broker_transactions, [:transaction_type])
    create index(:broker_transactions, [:isin])
    create index(:broker_transactions, [:trade_date])
    create index(:broker_transactions, [:confirmation_number])
    create unique_index(:broker_transactions, [:broker, :external_id])
  end
end
