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
    :symbol,
    :asset_category,
    :listing_exchange,
    :currency,
    :multiplier,
    :type,
    :metadata,
    :sector,
    :industry,
    :country,
    :logo_url,
    :web_url,
    :dividend_rate,
    :dividend_yield,
    :dividend_frequency,
    :ex_dividend_date,
    :payout_ratio,
    :dividend_source,
    :dividend_updated_at,
    :dividend_per_payment,
    :payments_per_year
  ]

  schema "instruments" do
    field :isin, :string
    field :cusip, :string
    field :conid, :integer
    field :figi, :string
    field :name, :string
    field :symbol, :string
    field :asset_category, :string
    field :listing_exchange, :string
    field :currency, :string
    field :multiplier, :decimal, default: Decimal.new("1")
    field :type, :string
    field :metadata, :map, default: %{}
    field :sector, :string
    field :industry, :string
    field :country, :string
    field :logo_url, :string
    field :web_url, :string
    field :dividend_rate, :decimal
    field :dividend_yield, :decimal
    field :dividend_frequency, :string
    field :ex_dividend_date, :date
    field :payout_ratio, :decimal
    field :dividend_source, :string
    field :dividend_updated_at, :utc_datetime
    field :dividend_per_payment, :decimal
    field :payments_per_year, :integer

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
