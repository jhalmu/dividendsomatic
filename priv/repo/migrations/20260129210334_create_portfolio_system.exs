defmodule Dividendsomatic.Repo.Migrations.CreatePortfolioSystem do
  use Ecto.Migration

  def change do
    create table(:portfolio_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :report_date, :date, null: false
      add :raw_csv_data, :text

      timestamps()
    end

    create unique_index(:portfolio_snapshots, [:report_date])

    create table(:holdings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :portfolio_snapshot_id,
          references(:portfolio_snapshots, type: :binary_id, on_delete: :delete_all), null: false

      # All CSV fields
      add :report_date, :date, null: false
      add :currency_primary, :string
      add :symbol, :string, null: false
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

      timestamps()
    end

    create index(:holdings, [:portfolio_snapshot_id])
    create index(:holdings, [:symbol])
    create index(:holdings, [:report_date])
  end
end
