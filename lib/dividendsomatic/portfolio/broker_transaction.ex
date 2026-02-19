defmodule Dividendsomatic.Portfolio.BrokerTransaction do
  @moduledoc """
  Schema for raw broker transactions.

  Stores normalized transaction data from any broker (Nordnet, IBKR).
  Serves as the source of truth for deriving dividends, sold positions, and costs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @transaction_types ~w(
    buy sell dividend withholding_tax foreign_tax
    deposit withdrawal fx_buy fx_sell loan_interest
    capital_interest interest_correction corporate_action
  )

  schema "legacy_broker_transactions" do
    field :external_id, :string
    field :broker, :string
    field :transaction_type, :string
    field :raw_type, :string
    field :entry_date, :date
    field :trade_date, :date
    field :settlement_date, :date
    field :portfolio_id, :string
    field :security_name, :string
    field :isin, :string
    field :quantity, :decimal
    field :price, :decimal
    field :amount, :decimal
    field :interest, :decimal
    field :total_costs, :decimal
    field :commission, :decimal
    field :currency, :string
    field :acquisition_value, :decimal
    field :result, :decimal
    field :total_quantity, :decimal
    field :balance, :decimal
    field :exchange_rate, :decimal
    field :reference_fx_rate, :decimal
    field :description, :string
    field :confirmation_number, :string
    field :raw_data, :map

    timestamps()
  end

  @required_fields [:broker, :transaction_type, :raw_type]
  @optional_fields [
    :external_id,
    :entry_date,
    :trade_date,
    :settlement_date,
    :portfolio_id,
    :security_name,
    :isin,
    :quantity,
    :price,
    :amount,
    :interest,
    :total_costs,
    :commission,
    :currency,
    :acquisition_value,
    :result,
    :total_quantity,
    :balance,
    :exchange_rate,
    :reference_fx_rate,
    :description,
    :confirmation_number,
    :raw_data
  ]

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:transaction_type, @transaction_types)
    |> unique_constraint([:broker, :external_id],
      name: "broker_transactions_broker_external_id_index"
    )
  end

  def transaction_types, do: @transaction_types
end
