defmodule Dividendsomatic.Portfolio.Cost do
  @moduledoc """
  Schema for tracking trading costs.

  Stores commissions, withholding taxes, loan interest, and other costs
  extracted from broker transactions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @cost_types ~w(commission loan_interest withholding_tax foreign_tax capital_interest)

  schema "legacy_costs" do
    field :cost_type, :string
    field :date, :date
    field :amount, :decimal
    field :currency, :string, default: "EUR"
    field :symbol, :string
    field :isin, :string
    field :description, :string
    field :broker, :string

    belongs_to :broker_transaction, Dividendsomatic.Portfolio.BrokerTransaction

    timestamps()
  end

  @required_fields [:cost_type, :date, :amount, :currency, :broker]
  @optional_fields [:symbol, :isin, :description, :broker_transaction_id]

  @doc false
  def changeset(cost, attrs) do
    cost
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:cost_type, @cost_types)
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint([:broker_transaction_id],
      name: "costs_broker_transaction_id_index"
    )
  end

  def cost_types, do: @cost_types
end
