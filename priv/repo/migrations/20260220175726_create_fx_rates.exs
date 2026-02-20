defmodule Dividendsomatic.Repo.Migrations.CreateFxRates do
  use Ecto.Migration

  def change do
    create table(:fx_rates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :currency, :string, null: false
      add :rate, :decimal, null: false
      add :source, :string

      timestamps()
    end

    create unique_index(:fx_rates, [:date, :currency])
  end
end
