defmodule Dividendsomatic.Stocks.StockMetric do
  @moduledoc """
  Schema for cached stock financial metrics from Finnhub.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stock_metrics" do
    field :symbol, :string
    field :pe_ratio, :decimal
    field :pb_ratio, :decimal
    field :eps, :decimal
    field :roe, :decimal
    field :roa, :decimal
    field :net_margin, :decimal
    field :operating_margin, :decimal
    field :debt_to_equity, :decimal
    field :current_ratio, :decimal
    field :fcf_margin, :decimal
    field :beta, :decimal
    field :payout_ratio, :decimal
    field :fetched_at, :utc_datetime

    timestamps()
  end

  @required_fields [:symbol, :fetched_at]
  @optional_fields [
    :pe_ratio,
    :pb_ratio,
    :eps,
    :roe,
    :roa,
    :net_margin,
    :operating_margin,
    :debt_to_equity,
    :current_ratio,
    :fcf_margin,
    :beta,
    :payout_ratio
  ]

  @doc false
  def changeset(metric, attrs) do
    metric
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:symbol)
  end
end
