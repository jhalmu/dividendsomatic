defmodule Dividendsomatic.Repo.Migrations.AddDividendFieldsToInstruments do
  use Ecto.Migration

  def change do
    alter table(:instruments) do
      add :dividend_rate, :decimal
      add :dividend_yield, :decimal
      add :dividend_frequency, :string
      add :ex_dividend_date, :date
      add :payout_ratio, :decimal
      add :dividend_source, :string
      add :dividend_updated_at, :utc_datetime
    end
  end
end
