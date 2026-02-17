defmodule Dividendsomatic.Repo.Migrations.AddAmountTypeToDividends do
  use Ecto.Migration

  def change do
    alter table(:dividends) do
      add :amount_type, :string, default: "per_share", null: false
    end
  end
end
