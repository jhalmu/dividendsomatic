defmodule Dividendsomatic.Repo.Migrations.AddHoldingsUniqueIndex do
  use Ecto.Migration

  def change do
    # ISIN-based deduplication: within a snapshot, same ISIN can't appear twice for same date
    create unique_index(:holdings, [:portfolio_snapshot_id, :isin, :report_date],
             name: :holdings_snapshot_isin_date_index,
             where: "isin IS NOT NULL"
           )

    # Fallback for old data without ISIN: uses symbol+report_date
    create unique_index(:holdings, [:portfolio_snapshot_id, :symbol, :report_date],
             name: :holdings_snapshot_symbol_date_index,
             where: "isin IS NULL"
           )
  end
end
