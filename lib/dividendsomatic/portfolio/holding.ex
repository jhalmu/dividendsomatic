defmodule Dividendsomatic.Portfolio.Holding do
  @moduledoc """
  Legacy schema for the old holdings table (now legacy_holdings).

  Retained for data migration and backward compatibility during transition.
  New code should use `Dividendsomatic.Portfolio.Position` instead.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "legacy_holdings" do
    field :portfolio_snapshot_id, :binary_id

    field :report_date, :date
    field :currency_primary, :string
    field :symbol, :string
    field :description, :string
    field :sub_category, :string
    field :quantity, :decimal
    field :mark_price, :decimal
    field :position_value, :decimal
    field :cost_basis_price, :decimal
    field :cost_basis_money, :decimal
    field :open_price, :decimal
    field :percent_of_nav, :decimal
    field :fifo_pnl_unrealized, :decimal
    field :listing_exchange, :string
    field :asset_class, :string
    field :fx_rate_to_base, :decimal
    field :isin, :string
    field :figi, :string
    field :holding_period_date_time, :string
    field :identifier_key, :string

    timestamps()
  end

  def changeset(holding, attrs) do
    holding
    |> cast(attrs, [
      :portfolio_snapshot_id,
      :report_date,
      :currency_primary,
      :symbol,
      :description,
      :sub_category,
      :quantity,
      :mark_price,
      :position_value,
      :cost_basis_price,
      :cost_basis_money,
      :open_price,
      :percent_of_nav,
      :fifo_pnl_unrealized,
      :listing_exchange,
      :asset_class,
      :fx_rate_to_base,
      :isin,
      :figi,
      :holding_period_date_time,
      :identifier_key
    ])
    |> validate_required([:portfolio_snapshot_id, :report_date, :symbol])
  end
end
