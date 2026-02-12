defmodule Dividendsomatic.Repo.Migrations.CreateSymbolMappings do
  use Ecto.Migration

  def change do
    create table(:symbol_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :isin, :string, null: false
      add :finnhub_symbol, :string
      add :security_name, :string
      add :currency, :string
      add :exchange, :string
      add :status, :string, null: false, default: "pending"
      add :notes, :string

      timestamps()
    end

    create unique_index(:symbol_mappings, [:isin])
    create index(:symbol_mappings, [:status])
  end
end
