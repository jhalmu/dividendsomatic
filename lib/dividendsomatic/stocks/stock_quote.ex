defmodule Dividendsomatic.Stocks.StockQuote do
  @moduledoc """
  Schema for cached stock quotes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stock_quotes" do
    field :symbol, :string
    field :current_price, :decimal
    field :change, :decimal
    field :percent_change, :decimal
    field :high, :decimal
    field :low, :decimal
    field :open, :decimal
    field :previous_close, :decimal
    field :fetched_at, :utc_datetime

    timestamps()
  end

  @required_fields [:symbol, :fetched_at]
  @optional_fields [:current_price, :change, :percent_change, :high, :low, :open, :previous_close]

  @doc false
  def changeset(quote, attrs) do
    quote
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:symbol)
  end
end
