defmodule Dividendsomatic.Repo.Migrations.AddIsinToDividendsAndSoldPositions do
  use Ecto.Migration

  def change do
    alter table(:dividends) do
      add :isin, :string
    end

    alter table(:sold_positions) do
      add :isin, :string
      add :source, :string
    end

    create index(:dividends, [:isin])
    create index(:sold_positions, [:isin])
  end
end
