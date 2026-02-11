defmodule Dividendsomatic.Repo.Migrations.AddHoldingPeriodAndIdentifierKey do
  use Ecto.Migration

  def change do
    alter table(:holdings) do
      add :holding_period_date_time, :string
      add :identifier_key, :string
    end

    create index(:holdings, [:identifier_key])
  end
end
