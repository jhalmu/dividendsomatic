defmodule Dividendsomatic.Repo.Migrations.AddMarginEquitySnapshots do
  use Ecto.Migration

  def change do
    create table(:margin_equity_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :cash_balance, :decimal
      add :margin_loan, :decimal
      add :net_liquidation_value, :decimal
      add :own_equity, :decimal
      add :leverage_ratio, :decimal
      add :loan_to_value, :decimal
      add :source, :string, null: false
      add :metadata, :map

      timestamps()
    end

    create unique_index(:margin_equity_snapshots, [:date])
  end
end
