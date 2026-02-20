defmodule Dividendsomatic.Repo.Migrations.AddEnrichmentFieldsToInstruments do
  use Ecto.Migration

  def change do
    alter table(:instruments) do
      add :sector, :string
      add :industry, :string
      add :country, :string
      add :logo_url, :string
      add :web_url, :string
    end
  end
end
