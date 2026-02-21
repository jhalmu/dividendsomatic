defmodule Dividendsomatic.Repo.Migrations.AddSymbolToInstruments do
  use Ecto.Migration

  def change do
    alter table(:instruments) do
      add :symbol, :string
    end

    create index(:instruments, [:symbol])
  end
end
