defmodule Dividendsomatic.Repo.Migrations.CreateCosts do
  use Ecto.Migration

  def change do
    create table(:costs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cost_type, :string, null: false
      add :date, :date, null: false
      add :amount, :decimal, null: false
      add :currency, :string, default: "EUR"
      add :symbol, :string
      add :isin, :string
      add :description, :string
      add :broker, :string, null: false

      add :broker_transaction_id,
          references(:broker_transactions, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:costs, [:broker_transaction_id])
    create index(:costs, [:cost_type])
    create index(:costs, [:isin])
  end
end
