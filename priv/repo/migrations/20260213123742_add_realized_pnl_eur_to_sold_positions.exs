defmodule Dividendsomatic.Repo.Migrations.AddRealizedPnlEurToSoldPositions do
  use Ecto.Migration

  def change do
    alter table(:sold_positions) do
      add :realized_pnl_eur, :decimal
      add :exchange_rate_to_eur, :decimal
    end

    # Backfill EUR records immediately (rate = 1.0, pnl_eur = pnl)
    execute(
      "UPDATE sold_positions SET realized_pnl_eur = realized_pnl, exchange_rate_to_eur = 1.0 WHERE currency = 'EUR'",
      "SELECT 1"
    )
  end
end
