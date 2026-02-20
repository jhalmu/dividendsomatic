defmodule Dividendsomatic.Repo.Migrations.AddCorporateActionFields do
  use Ecto.Migration

  def change do
    alter table(:corporate_actions) do
      add :external_id, :string
      add :currency, :string
      add :proceeds, :decimal
    end

    create unique_index(:corporate_actions, [:external_id])
  end
end
