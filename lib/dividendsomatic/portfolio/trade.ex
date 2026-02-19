defmodule Dividendsomatic.Portfolio.Trade do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [
    :external_id,
    :instrument_id,
    :trade_date,
    :quantity,
    :price,
    :amount,
    :currency
  ]
  @optional_fields [
    :trade_time,
    :settlement_date,
    :commission,
    :fx_rate,
    :asset_category,
    :exchange,
    :description,
    :raw_data
  ]

  schema "trades" do
    belongs_to :instrument, Dividendsomatic.Portfolio.Instrument
    field :external_id, :string
    field :trade_date, :date
    field :trade_time, :time
    field :settlement_date, :date
    field :quantity, :decimal
    field :price, :decimal
    field :amount, :decimal
    field :commission, :decimal, default: Decimal.new("0")
    field :currency, :string
    field :fx_rate, :decimal
    field :asset_category, :string
    field :exchange, :string
    field :description, :string
    field :raw_data, :map, default: %{}

    timestamps()
  end

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:external_id)
    |> foreign_key_constraint(:instrument_id)
  end
end
