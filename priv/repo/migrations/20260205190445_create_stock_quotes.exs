defmodule Dividendsomatic.Repo.Migrations.CreateStockQuotes do
  use Ecto.Migration

  def change do
    create table(:stock_quotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :current_price, :decimal
      add :change, :decimal
      add :percent_change, :decimal
      add :high, :decimal
      add :low, :decimal
      add :open, :decimal
      add :previous_close, :decimal
      add :fetched_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:stock_quotes, [:symbol])

    create table(:company_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :name, :string
      add :country, :string
      add :currency, :string
      add :exchange, :string
      add :ipo_date, :date
      add :market_cap, :decimal
      add :sector, :string
      add :industry, :string
      add :logo_url, :string
      add :web_url, :string
      add :fetched_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:company_profiles, [:symbol])
  end
end
