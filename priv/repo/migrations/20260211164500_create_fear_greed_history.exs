defmodule Dividendsomatic.Repo.Migrations.CreateFearGreedHistory do
  use Ecto.Migration

  def change do
    create table(:fear_greed_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :value, :integer, null: false
      add :classification, :string, null: false

      timestamps()
    end

    create unique_index(:fear_greed_history, [:date])
  end
end
