defmodule Dividendsomatic.Repo.Migrations.DropLegacySymbolMappings do
  use Ecto.Migration

  @moduledoc """
  Drop legacy_symbol_mappings table.

  72 resolved mappings migrated to instrument_aliases (34 had matching instruments,
  38 had no instrument in DB). 43 unmappable entries skipped by design.
  """

  def up do
    drop_if_exists table(:legacy_symbol_mappings)
  end

  def down do
    create table(:legacy_symbol_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :isin, :string
      add :finnhub_symbol, :string
      add :security_name, :string
      add :currency, :string
      add :exchange, :string
      add :status, :string, default: "pending"
      add :notes, :string
      timestamps()
    end

    create unique_index(:legacy_symbol_mappings, [:isin], name: "symbol_mappings_isin_index")
  end
end
