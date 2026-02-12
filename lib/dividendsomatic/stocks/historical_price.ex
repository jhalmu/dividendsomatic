defmodule Dividendsomatic.Stocks.HistoricalPrice do
  @moduledoc """
  Schema for cached historical daily price data.

  Stores OHLCV candle data fetched from Finnhub for portfolio reconstruction.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "historical_prices" do
    field :symbol, :string
    field :isin, :string
    field :date, :date
    field :open, :decimal
    field :high, :decimal
    field :low, :decimal
    field :close, :decimal
    field :volume, :integer
    field :source, :string, default: "finnhub"

    timestamps()
  end

  @required_fields [:symbol, :date]
  @optional_fields [:isin, :open, :high, :low, :close, :volume, :source]

  @doc false
  def changeset(price, attrs) do
    price
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:symbol, :date])
  end
end
