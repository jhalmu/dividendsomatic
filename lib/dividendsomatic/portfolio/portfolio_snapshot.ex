defmodule Dividendsomatic.Portfolio.PortfolioSnapshot do
  @moduledoc """
  Schema representing a daily portfolio snapshot.

  One row per date. The single source of truth for portfolio history.
  Precomputed total_value/total_cost for efficient chart queries.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_snapshots" do
    field :date, :date
    field :total_value, :decimal
    field :total_cost, :decimal
    field :base_currency, :string, default: "EUR"
    field :source, :string
    field :data_quality, :string, default: "actual"
    field :positions_count, :integer, default: 0
    field :metadata, :map

    has_many :positions, Dividendsomatic.Portfolio.Position

    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :date,
      :total_value,
      :total_cost,
      :base_currency,
      :source,
      :data_quality,
      :positions_count,
      :metadata
    ])
    |> validate_required([:date, :source])
    |> validate_inclusion(:data_quality, ~w(actual reconstructed estimated))
    |> unique_constraint(:date)
  end
end
