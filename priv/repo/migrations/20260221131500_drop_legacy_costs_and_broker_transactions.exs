defmodule Dividendsomatic.Repo.Migrations.DropLegacyCostsAndBrokerTransactions do
  use Ecto.Migration

  @moduledoc """
  Drop legacy_costs and legacy_broker_transactions tables.

  legacy_costs must be dropped first due to FK constraint on broker_transaction_id.

  legacy_costs: 4,598 records (3,266 commissions already on trades, 1,174 taxes
  already on dividend_payments, 158 interest migrated to cash_flows).

  legacy_broker_transactions: 7,407 records (3,818 trades, 25 dividend_payments,
  257 deposit cash_flows, 159 interest cash_flows, 98 corporate_actions migrated;
  758 trades skipped for missing instruments, 399 FX skipped).
  """

  def up do
    # Drop costs first (has FK to broker_transactions)
    drop_if_exists table(:legacy_costs)
    drop_if_exists table(:legacy_broker_transactions)
  end

  def down do
    create table(:legacy_broker_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string
      add :broker, :string
      add :transaction_type, :string
      add :raw_type, :string
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

    create table(:legacy_costs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cost_type, :string
      add :date, :date
      add :amount, :decimal
      add :currency, :string, default: "EUR"
      add :symbol, :string
      add :isin, :string
      add :description, :string
      add :broker, :string
      add :broker_transaction_id, references(:legacy_broker_transactions, type: :binary_id)
      timestamps()
    end
  end
end
