defmodule Dividendsomatic.Repo.Migrations.CreateDividends do
  use Ecto.Migration

  def change do
    create table(:dividends, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :ex_date, :date, null: false
      add :pay_date, :date
      add :amount, :decimal, null: false
      add :currency, :string, null: false, default: "EUR"
      add :source, :string

      timestamps()
    end

    create index(:dividends, [:symbol])
    create index(:dividends, [:ex_date])
    create index(:dividends, [:pay_date])
    create unique_index(:dividends, [:symbol, :ex_date, :amount], name: :dividends_unique)
  end
end
