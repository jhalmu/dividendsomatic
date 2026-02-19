defmodule Dividendsomatic.Repo.Migrations.ArchiveLegacyTables do
  use Ecto.Migration

  def change do
    # Archive old tables replaced by the clean IBKR-derived tables:
    #   instruments, instrument_aliases, trades, dividend_payments, cash_flows, corporate_actions
    #
    # Data preserved under legacy_ prefix for comparison/audit.
    # Can be dropped in a future migration once verified.

    rename table(:dividends), to: table(:legacy_dividends)
    rename table(:costs), to: table(:legacy_costs)
    rename table(:broker_transactions), to: table(:legacy_broker_transactions)
    rename table(:symbol_mappings), to: table(:legacy_symbol_mappings)
  end
end
