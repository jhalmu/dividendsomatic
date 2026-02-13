defmodule Dividendsomatic.Repo.Migrations.AddIdentifierKeyToSoldPositions do
  use Ecto.Migration

  def change do
    alter table(:sold_positions) do
      add :identifier_key, :string, null: false, default: ""
    end

    create index(:sold_positions, [:identifier_key])
  end
end
