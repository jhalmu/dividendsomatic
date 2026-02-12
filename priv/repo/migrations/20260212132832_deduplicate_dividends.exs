defmodule Dividendsomatic.Repo.Migrations.DeduplicateDividends do
  use Ecto.Migration

  def up do
    # Keep one row per (symbol, ex_date), delete float-drift duplicates.
    # For each group, keep the earliest-inserted row.
    execute """
    DELETE FROM dividends
    WHERE id IN (
      SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY symbol, ex_date ORDER BY inserted_at ASC) AS rn
        FROM dividends
      ) ranked
      WHERE rn > 1
    )
    """

    # Drop old index that allowed float-drift duplicates
    drop_if_exists unique_index(:dividends, [:symbol, :ex_date, :amount], name: :dividends_unique)

    # New stricter index: one dividend per symbol per ex_date
    create unique_index(:dividends, [:symbol, :ex_date], name: :dividends_unique)
  end

  def down do
    drop_if_exists unique_index(:dividends, [:symbol, :ex_date], name: :dividends_unique)
    create unique_index(:dividends, [:symbol, :ex_date, :amount], name: :dividends_unique)
  end
end
