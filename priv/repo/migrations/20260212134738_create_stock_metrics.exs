defmodule Dividendsomatic.Repo.Migrations.CreateStockMetrics do
  use Ecto.Migration

  def change do
    create table(:stock_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :pe_ratio, :decimal
      add :pb_ratio, :decimal
      add :eps, :decimal
      add :roe, :decimal
      add :roa, :decimal
      add :net_margin, :decimal
      add :operating_margin, :decimal
      add :debt_to_equity, :decimal
      add :current_ratio, :decimal
      add :fcf_margin, :decimal
      add :beta, :decimal
      add :payout_ratio, :decimal
      add :fetched_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:stock_metrics, [:symbol])
  end
end
