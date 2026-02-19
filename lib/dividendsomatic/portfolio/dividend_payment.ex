defmodule Dividendsomatic.Portfolio.DividendPayment do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [
    :external_id,
    :instrument_id,
    :pay_date,
    :gross_amount,
    :net_amount,
    :currency
  ]
  @optional_fields [
    :ex_date,
    :withholding_tax,
    :fx_rate,
    :amount_eur,
    :quantity,
    :per_share,
    :description,
    :raw_data
  ]

  schema "dividend_payments" do
    belongs_to :instrument, Dividendsomatic.Portfolio.Instrument
    field :external_id, :string
    field :ex_date, :date
    field :pay_date, :date
    field :gross_amount, :decimal
    field :withholding_tax, :decimal, default: Decimal.new("0")
    field :net_amount, :decimal
    field :currency, :string
    field :fx_rate, :decimal
    field :amount_eur, :decimal
    field :quantity, :decimal
    field :per_share, :decimal
    field :description, :string
    field :raw_data, :map, default: %{}

    timestamps()
  end

  def changeset(dividend_payment, attrs) do
    dividend_payment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:external_id)
    |> foreign_key_constraint(:instrument_id)
  end
end
