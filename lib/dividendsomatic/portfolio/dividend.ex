defmodule Dividendsomatic.Portfolio.Dividend do
  @moduledoc """
  Schema for dividend payments.

  Tracks dividend income from portfolio holdings.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dividends" do
    field :symbol, :string
    field :ex_date, :date
    field :pay_date, :date
    field :amount, :decimal
    field :currency, :string, default: "EUR"
    field :source, :string

    timestamps()
  end

  @required_fields [:symbol, :ex_date, :amount, :currency]
  @optional_fields [:pay_date, :source]

  @doc false
  def changeset(dividend, attrs) do
    dividend
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint([:symbol, :ex_date, :amount], name: :dividends_unique)
  end
end
