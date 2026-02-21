defmodule Dividendsomatic.Repo.Migrations.AddIsPrimaryToInstrumentAliases do
  use Ecto.Migration

  def change do
    alter table(:instrument_aliases) do
      add :is_primary, :boolean, default: false, null: false
    end

    # Only one primary alias per instrument
    create unique_index(:instrument_aliases, [:instrument_id],
             where: "is_primary = true",
             name: :instrument_aliases_one_primary_per_instrument
           )
  end
end
