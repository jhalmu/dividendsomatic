defmodule Dividendsomatic.Portfolio.CashFlow do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @flow_types ~w(deposit withdrawal interest fee other)

  @required_fields [:external_id, :flow_type, :date, :amount, :currency]
  @optional_fields [:fx_rate, :amount_eur, :description, :raw_data, :source]

  schema "cash_flows" do
    field :external_id, :string
    field :flow_type, :string
    field :date, :date
    field :amount, :decimal
    field :currency, :string
    field :fx_rate, :decimal
    field :amount_eur, :decimal
    field :description, :string
    field :source, :string
    field :raw_data, :map, default: %{}

    timestamps()
  end

  def changeset(cash_flow, attrs) do
    cash_flow
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:flow_type, @flow_types)
    |> unique_constraint(:external_id)
  end
end
