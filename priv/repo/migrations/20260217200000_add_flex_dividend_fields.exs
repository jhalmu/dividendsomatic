defmodule Dividendsomatic.Repo.Migrations.AddFlexDividendFields do
  use Ecto.Migration

  def change do
    alter table(:dividends) do
      add :figi, :string
      add :gross_rate, :decimal
      add :net_amount, :decimal
      add :quantity_at_record, :decimal
      add :fx_rate, :decimal
    end
  end
end
