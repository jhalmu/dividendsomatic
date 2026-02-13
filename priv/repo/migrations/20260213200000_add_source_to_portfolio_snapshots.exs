defmodule Dividendsomatic.Repo.Migrations.AddSourceToPortfolioSnapshots do
  use Ecto.Migration

  def change do
    alter table(:portfolio_snapshots) do
      add :source, :string
    end
  end
end
