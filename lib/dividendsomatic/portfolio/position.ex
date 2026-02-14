defmodule Dividendsomatic.Portfolio.Position do
  @moduledoc """
  Schema representing an individual position within a portfolio snapshot.

  Generic, broker-agnostic field names. Replaces the old Holding schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "positions" do
    belongs_to :portfolio_snapshot, Dividendsomatic.Portfolio.PortfolioSnapshot,
      foreign_key: :portfolio_snapshot_id

    field :date, :date

    # Identification
    field :isin, :string
    field :symbol, :string
    field :name, :string
    field :asset_class, :string
    field :exchange, :string

    # Position data
    field :quantity, :decimal
    field :price, :decimal
    field :value, :decimal
    field :cost_basis, :decimal
    field :cost_price, :decimal
    field :currency, :string, default: "EUR"
    field :fx_rate, :decimal

    # Computed/optional
    field :unrealized_pnl, :decimal
    field :weight, :decimal

    # Extended identifiers
    field :figi, :string

    # Source tracking
    field :data_source, :string

    timestamps()
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :portfolio_snapshot_id,
      :date,
      :isin,
      :symbol,
      :name,
      :asset_class,
      :exchange,
      :quantity,
      :price,
      :value,
      :cost_basis,
      :cost_price,
      :currency,
      :fx_rate,
      :unrealized_pnl,
      :weight,
      :figi,
      :data_source
    ])
    |> validate_required([:portfolio_snapshot_id, :date, :symbol, :quantity])
    |> unique_constraint([:portfolio_snapshot_id, :isin, :date],
      name: :positions_snapshot_isin_date_index
    )
    |> unique_constraint([:portfolio_snapshot_id, :symbol, :date],
      name: :positions_snapshot_symbol_date_index
    )
  end
end
