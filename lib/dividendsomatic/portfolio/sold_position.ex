defmodule Dividendsomatic.Portfolio.SoldPosition do
  @moduledoc """
  Schema for tracking sold positions.

  Used for "What-If" analysis to see hypothetical portfolio value
  if positions were never sold.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sold_positions" do
    field :symbol, :string
    field :description, :string
    field :quantity, :decimal
    field :purchase_price, :decimal
    field :purchase_date, :date
    field :sale_price, :decimal
    field :sale_date, :date
    field :currency, :string, default: "EUR"
    field :realized_pnl, :decimal
    field :notes, :string

    timestamps()
  end

  @required_fields [:symbol, :quantity, :purchase_price, :purchase_date, :sale_price, :sale_date]
  @optional_fields [:description, :currency, :realized_pnl, :notes]

  @doc false
  def changeset(sold_position, attrs) do
    sold_position
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:purchase_price, greater_than: 0)
    |> validate_number(:sale_price, greater_than: 0)
    |> calculate_realized_pnl()
  end

  defp calculate_realized_pnl(changeset) do
    quantity = get_field(changeset, :quantity)
    purchase_price = get_field(changeset, :purchase_price)
    sale_price = get_field(changeset, :sale_price)

    if quantity && purchase_price && sale_price do
      cost = Decimal.mult(quantity, purchase_price)
      proceeds = Decimal.mult(quantity, sale_price)
      pnl = Decimal.sub(proceeds, cost)
      put_change(changeset, :realized_pnl, pnl)
    else
      changeset
    end
  end
end
