defmodule Dividendsomatic.Repo.Migrations.CreateSoldPositions do
  use Ecto.Migration

  def change do
    create table(:sold_positions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :description, :string
      add :quantity, :decimal, null: false
      add :purchase_price, :decimal, null: false
      add :purchase_date, :date, null: false
      add :sale_price, :decimal, null: false
      add :sale_date, :date, null: false
      add :currency, :string, null: false, default: "EUR"
      add :realized_pnl, :decimal
      add :notes, :text

      timestamps()
    end

    create index(:sold_positions, [:symbol])
    create index(:sold_positions, [:sale_date])
  end
end
