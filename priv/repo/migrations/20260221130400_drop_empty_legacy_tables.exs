defmodule Dividendsomatic.Repo.Migrations.DropEmptyLegacyTables do
  use Ecto.Migration

  @moduledoc """
  Drop legacy_holdings and legacy_portfolio_snapshots.

  Both tables have been fully migrated to positions and portfolio_snapshots
  respectively, with 0 unique dates remaining. Verified by DATABASE_ANALYSIS.md.
  """

  def up do
    drop_if_exists table(:legacy_holdings)
    drop_if_exists table(:legacy_portfolio_snapshots)
  end

  def down do
    create table(:legacy_portfolio_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :report_date, :date
      add :raw_csv_data, :text
      add :source, :string
      timestamps()
    end

    create table(:legacy_holdings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :portfolio_snapshot_id, references(:legacy_portfolio_snapshots, type: :binary_id)
      add :report_date, :date
      add :currency_primary, :string
      add :symbol, :string
      add :description, :string
      add :sub_category, :string
      add :quantity, :decimal
      add :mark_price, :decimal
      add :position_value, :decimal
      add :cost_basis_price, :decimal
      add :cost_basis_money, :decimal
      add :open_price, :decimal
      add :percent_of_nav, :decimal
      add :fifo_pnl_unrealized, :decimal
      add :listing_exchange, :string
      add :asset_class, :string
      add :fx_rate_to_base, :decimal
      add :isin, :string
      add :figi, :string
      add :holding_period_date_time, :string
      add :identifier_key, :string
      timestamps()
    end
  end
end
