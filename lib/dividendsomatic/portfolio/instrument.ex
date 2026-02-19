defmodule Dividendsomatic.Portfolio.Instrument do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [:isin]
  @optional_fields [
    :cusip,
    :conid,
    :figi,
    :name,
    :asset_category,
    :listing_exchange,
    :currency,
    :multiplier,
    :type,
    :metadata
  ]

  schema "instruments" do
    field :isin, :string
    field :cusip, :string
    field :conid, :integer
    field :figi, :string
    field :name, :string
    field :asset_category, :string
    field :listing_exchange, :string
    field :currency, :string
    field :multiplier, :decimal, default: Decimal.new("1")
    field :type, :string
    field :metadata, :map, default: %{}

    has_many :aliases, Dividendsomatic.Portfolio.InstrumentAlias
    has_many :trades, Dividendsomatic.Portfolio.Trade
    has_many :dividend_payments, Dividendsomatic.Portfolio.DividendPayment
    has_many :corporate_actions, Dividendsomatic.Portfolio.CorporateAction

    timestamps()
  end

  def changeset(instrument, attrs) do
    instrument
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:isin)
  end
end
