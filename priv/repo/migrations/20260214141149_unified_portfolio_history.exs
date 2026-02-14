defmodule Dividendsomatic.Repo.Migrations.UnifiedPortfolioHistory do
  use Ecto.Migration

  @moduledoc """
  Unified portfolio history schema.

  Renames old tables to legacy_* and creates new generic tables:
  - portfolio_snapshots: one row per date, precomputed totals, source/quality tracking
  - positions: per-security positions with generic field names
  """

  def change do
    # Phase 1: Rename old tables to legacy_*
    rename table(:holdings), to: table(:legacy_holdings)
    rename table(:portfolio_snapshots), to: table(:legacy_portfolio_snapshots)

    # Phase 2: Create new portfolio_snapshots table
    create table(:portfolio_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :total_value, :decimal
      add :total_cost, :decimal
      add :base_currency, :string, default: "EUR"
      add :source, :string, null: false
      add :data_quality, :string, null: false, default: "actual"
      add :positions_count, :integer, default: 0
      add :metadata, :map

      timestamps()
    end

    create unique_index(:portfolio_snapshots, [:date])
    create index(:portfolio_snapshots, [:source])

    # Phase 3: Create new positions table
    create table(:positions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :portfolio_snapshot_id,
          references(:portfolio_snapshots, type: :binary_id, on_delete: :delete_all),
          null: false

      add :date, :date, null: false

      # Identification
      add :isin, :string
      add :symbol, :string, null: false
      add :name, :string
      add :asset_class, :string
      add :exchange, :string

      # Position data
      add :quantity, :decimal, null: false
      add :price, :decimal
      add :value, :decimal
      add :cost_basis, :decimal
      add :cost_price, :decimal
      add :currency, :string, default: "EUR"
      add :fx_rate, :decimal

      # Computed/optional
      add :unrealized_pnl, :decimal
      add :weight, :decimal

      # Extended identifiers
      add :figi, :string

      # Source tracking
      add :data_source, :string

      timestamps()
    end

    create index(:positions, [:portfolio_snapshot_id])
    create index(:positions, [:isin])
    create index(:positions, [:date])

    create unique_index(:positions, [:portfolio_snapshot_id, :isin, :date],
             name: :positions_snapshot_isin_date_index
           )

    create unique_index(:positions, [:portfolio_snapshot_id, :symbol, :date],
             name: :positions_snapshot_symbol_date_index
           )
  end
end
