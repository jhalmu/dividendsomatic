defmodule Dividendsomatic.Repo.Migrations.DropLegacyDividends do
  use Ecto.Migration

  @moduledoc """
  Drop legacy_dividends table.

  332 broker records migrated to dividend_payments (15 new, 285 already existed, 32 no instrument).
  5,835 yfinance records archived to data_archive/yfinance_dividend_history.json.
  """

  def up do
    drop_if_exists table(:legacy_dividends)
  end

  def down do
    create table(:legacy_dividends, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string
      add :ex_date, :date
      add :pay_date, :date
      add :amount, :decimal
      add :currency, :string, default: "EUR"
      add :source, :string
      add :isin, :string
      add :amount_type, :string, default: "per_share"
      add :figi, :string
      add :gross_rate, :decimal
      add :net_amount, :decimal
      add :quantity_at_record, :decimal
      add :fx_rate, :decimal
      timestamps()
    end
  end
end
