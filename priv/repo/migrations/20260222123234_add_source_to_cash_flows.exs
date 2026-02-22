defmodule Dividendsomatic.Repo.Migrations.AddSourceToCashFlows do
  use Ecto.Migration

  def change do
    alter table(:cash_flows) do
      add :source, :string
    end

    # Tag all existing records as IBKR (Nordnet was cleaned out)
    execute "UPDATE cash_flows SET source = 'ibkr'", ""

    create index(:cash_flows, [:source])
  end
end
