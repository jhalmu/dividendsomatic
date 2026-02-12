defmodule Dividendsomatic.Repo.Migrations.CreateHistoricalPrices do
  use Ecto.Migration

  def change do
    create table(:historical_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :isin, :string
      add :date, :date, null: false
      add :open, :decimal
      add :high, :decimal
      add :low, :decimal
      add :close, :decimal
      add :volume, :bigint
      add :source, :string, default: "finnhub"

      timestamps()
    end

    create unique_index(:historical_prices, [:symbol, :date])
    create index(:historical_prices, [:isin])
    create index(:historical_prices, [:date])
  end
end
