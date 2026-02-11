defmodule Dividendsomatic.Repo.Migrations.CreateCompanyNotes do
  use Ecto.Migration

  def change do
    create table(:company_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :isin, :string, null: false
      add :symbol, :string
      add :name, :string
      add :asset_type, :string, default: "stock"
      add :notes_markdown, :text
      add :thesis, :text
      add :tags, {:array, :string}, default: []
      add :watchlist, :boolean, default: false

      timestamps()
    end

    create unique_index(:company_notes, [:isin])
  end
end
