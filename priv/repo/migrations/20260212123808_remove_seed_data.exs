defmodule Dividendsomatic.Repo.Migrations.RemoveSeedData do
  use Ecto.Migration

  def up do
    # All sold_positions are seed data (no CSV import path exists yet)
    execute "DELETE FROM sold_positions"

    # Seed dividends are tagged with source = 'seed_data'
    execute "DELETE FROM dividends WHERE source = 'seed_data'"
  end

  def down do
    # Seed data is not restorable — intentional one-way cleanup
  end
end
