defmodule Dividendsomatic.Portfolio.SchemaIntegrity do
  @moduledoc """
  Schema-level integrity checks for the portfolio database.

  Checks:
  - Orphaned records (instruments with no trades/positions, positions with no snapshot)
  - Null required fields (dividend_payments missing amount_eur, instruments missing currency)
  - FK integrity (trades/dividends pointing to non-existent instruments)
  - Duplicate detection (duplicate external_ids, duplicate snapshot dates)
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Repo

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    CorporateAction,
    DividendPayment,
    Instrument,
    InstrumentAlias,
    PortfolioSnapshot,
    Position,
    SoldPosition,
    Trade
  }

  @doc """
  Run all schema integrity checks. Returns a map of check results.
  """
  def check_all do
    checks = [
      orphan_check(),
      null_field_check(),
      fk_integrity_check(),
      duplicate_check(),
      alias_quality_check()
    ]

    issues = List.flatten(checks)

    %{
      total_checks: 5,
      total_issues: length(issues),
      issues: issues,
      by_severity: Enum.frequencies_by(issues, & &1.severity),
      by_check: Enum.frequencies_by(issues, & &1.check)
    }
  end

  @doc """
  Check for orphaned records.
  """
  def orphan_check do
    issues = []

    # Instruments with no trades AND no positions AND no dividend_payments
    orphan_instruments =
      from(i in Instrument,
        left_join: t in Trade,
        on: t.instrument_id == i.id,
        left_join: dp in DividendPayment,
        on: dp.instrument_id == i.id,
        where: is_nil(t.id) and is_nil(dp.id),
        select: %{isin: i.isin, name: i.name}
      )
      |> Repo.all()

    issues =
      if orphan_instruments != [] do
        count = length(orphan_instruments)

        [
          %{
            check: :orphan_instruments,
            severity: :info,
            count: count,
            message: "#{count} instruments with no trades or dividend payments",
            details: Enum.take(orphan_instruments, 10)
          }
          | issues
        ]
      else
        issues
      end

    # Positions with no snapshot
    orphan_positions =
      from(p in Position,
        left_join: s in PortfolioSnapshot,
        on: p.portfolio_snapshot_id == s.id,
        where: is_nil(s.id),
        select: count()
      )
      |> Repo.one()

    issues =
      if orphan_positions > 0 do
        [
          %{
            check: :orphan_positions,
            severity: :warning,
            count: orphan_positions,
            message: "#{orphan_positions} positions with no parent snapshot"
          }
          | issues
        ]
      else
        issues
      end

    # Instrument aliases with no instrument
    orphan_aliases =
      from(a in InstrumentAlias,
        left_join: i in Instrument,
        on: a.instrument_id == i.id,
        where: is_nil(i.id),
        select: count()
      )
      |> Repo.one()

    if orphan_aliases > 0 do
      [
        %{
          check: :orphan_aliases,
          severity: :warning,
          count: orphan_aliases,
          message: "#{orphan_aliases} instrument aliases with no parent instrument"
        }
        | issues
      ]
    else
      issues
    end
  end

  @doc """
  Check for null fields that should be populated.
  """
  def null_field_check do
    issues = []

    # Dividend payments missing amount_eur
    dp_no_eur =
      from(dp in DividendPayment, where: is_nil(dp.amount_eur), select: count())
      |> Repo.one()

    issues =
      if dp_no_eur > 0 do
        [
          %{
            check: :null_amount_eur,
            severity: :info,
            count: dp_no_eur,
            message: "#{dp_no_eur} dividend payments missing amount_eur"
          }
          | issues
        ]
      else
        issues
      end

    # Dividend payments missing fx_rate (for non-EUR currencies)
    dp_no_fx =
      from(dp in DividendPayment,
        where: is_nil(dp.fx_rate) and dp.currency != "EUR",
        select: count()
      )
      |> Repo.one()

    issues =
      if dp_no_fx > 0 do
        [
          %{
            check: :null_fx_rate,
            severity: :warning,
            count: dp_no_fx,
            message: "#{dp_no_fx} non-EUR dividend payments missing fx_rate"
          }
          | issues
        ]
      else
        issues
      end

    # Instruments missing currency
    inst_no_currency =
      from(i in Instrument, where: is_nil(i.currency), select: count())
      |> Repo.one()

    issues =
      if inst_no_currency > 0 do
        [
          %{
            check: :null_instrument_currency,
            severity: :warning,
            count: inst_no_currency,
            message: "#{inst_no_currency} instruments missing currency"
          }
          | issues
        ]
      else
        issues
      end

    # Instruments missing symbol
    inst_no_symbol =
      from(i in Instrument, where: is_nil(i.symbol), select: count())
      |> Repo.one()

    issues =
      if inst_no_symbol > 0 do
        [
          %{
            check: :null_instrument_symbol,
            severity: :info,
            count: inst_no_symbol,
            message: "#{inst_no_symbol} instruments missing symbol"
          }
          | issues
        ]
      else
        issues
      end

    # Instruments missing ISIN
    inst_no_isin =
      from(i in Instrument, where: is_nil(i.isin), select: count())
      |> Repo.one()

    issues =
      if inst_no_isin > 0 do
        [
          %{
            check: :null_instrument_isin,
            severity: :warning,
            count: inst_no_isin,
            message: "#{inst_no_isin} instruments missing ISIN"
          }
          | issues
        ]
      else
        issues
      end

    # Dividend payments on instruments missing ISIN
    dp_no_isin =
      from(dp in DividendPayment,
        join: i in Instrument,
        on: dp.instrument_id == i.id,
        where: is_nil(i.isin),
        select: count()
      )
      |> Repo.one()

    issues =
      if dp_no_isin > 0 do
        [
          %{
            check: :null_dividend_instrument_isin,
            severity: :warning,
            count: dp_no_isin,
            message: "#{dp_no_isin} dividend payments on instruments missing ISIN"
          }
          | issues
        ]
      else
        issues
      end

    # Positions missing ISIN
    pos_no_isin =
      from(p in Position, where: is_nil(p.isin), select: count())
      |> Repo.one()

    issues =
      if pos_no_isin > 0 do
        [
          %{
            check: :null_position_isin,
            severity: :info,
            count: pos_no_isin,
            message: "#{pos_no_isin} positions missing ISIN"
          }
          | issues
        ]
      else
        issues
      end

    # Sold positions missing ISIN
    sold_no_isin =
      from(sp in SoldPosition, where: is_nil(sp.isin), select: count())
      |> Repo.one()

    if sold_no_isin > 0 do
      [
        %{
          check: :null_sold_isin,
          severity: :warning,
          count: sold_no_isin,
          message: "#{sold_no_isin} sold positions missing ISIN"
        }
        | issues
      ]
    else
      issues
    end
  end

  @doc """
  Check FK integrity (references to non-existent instruments).
  """
  def fk_integrity_check do
    issues = []

    # Trades pointing to non-existent instruments
    orphan_trades =
      from(t in Trade,
        left_join: i in Instrument,
        on: t.instrument_id == i.id,
        where: is_nil(i.id),
        select: count()
      )
      |> Repo.one()

    issues =
      if orphan_trades > 0 do
        [
          %{
            check: :fk_trade_instrument,
            severity: :error,
            count: orphan_trades,
            message: "#{orphan_trades} trades pointing to non-existent instruments"
          }
          | issues
        ]
      else
        issues
      end

    # Dividend payments pointing to non-existent instruments
    orphan_divs =
      from(dp in DividendPayment,
        left_join: i in Instrument,
        on: dp.instrument_id == i.id,
        where: is_nil(i.id),
        select: count()
      )
      |> Repo.one()

    issues =
      if orphan_divs > 0 do
        [
          %{
            check: :fk_dividend_instrument,
            severity: :error,
            count: orphan_divs,
            message: "#{orphan_divs} dividend payments pointing to non-existent instruments"
          }
          | issues
        ]
      else
        issues
      end

    # Corporate actions pointing to non-existent instruments
    orphan_ca =
      from(ca in CorporateAction,
        where: not is_nil(ca.instrument_id),
        left_join: i in Instrument,
        on: ca.instrument_id == i.id,
        where: is_nil(i.id),
        select: count()
      )
      |> Repo.one()

    if orphan_ca > 0 do
      [
        %{
          check: :fk_corporate_action_instrument,
          severity: :error,
          count: orphan_ca,
          message: "#{orphan_ca} corporate actions pointing to non-existent instruments"
        }
        | issues
      ]
    else
      issues
    end
  end

  @doc """
  Check for duplicates.
  """
  def duplicate_check do
    [
      find_duplicates(Trade, :external_id, :duplicate_trade_external_ids, "trades"),
      find_duplicates(
        DividendPayment,
        :external_id,
        :duplicate_dividend_external_ids,
        "dividend payments"
      ),
      find_duplicates(PortfolioSnapshot, :date, :duplicate_snapshot_dates, "snapshots"),
      find_duplicates(CashFlow, :external_id, :duplicate_cashflow_external_ids, "cash flows")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp find_duplicates(schema, field, check_name, label) do
    dups =
      from(s in schema,
        group_by: field(s, ^field),
        having: count() > 1,
        select: count()
      )
      |> Repo.all()

    if dups != [] do
      count = length(dups)

      %{
        check: check_name,
        severity: :error,
        count: count,
        message: "#{count} duplicate #{field}s in #{label}"
      }
    end
  end

  @doc """
  Check alias quality: missing primary flags, comma-separated aliases.
  """
  def alias_quality_check do
    issues = []

    # Instruments with aliases but no primary alias
    instruments_without_primary =
      from(i in Instrument,
        join: a in InstrumentAlias,
        on: a.instrument_id == i.id,
        left_join: pa in InstrumentAlias,
        on: pa.instrument_id == i.id and pa.is_primary == true,
        where: is_nil(pa.id),
        select: %{isin: i.isin, symbol: i.symbol},
        distinct: true
      )
      |> Repo.all()

    issues =
      if instruments_without_primary != [] do
        count = length(instruments_without_primary)

        [
          %{
            check: :instruments_without_primary_alias,
            severity: :warning,
            count: count,
            message: "#{count} instruments have aliases but none marked primary",
            details: Enum.take(instruments_without_primary, 10)
          }
          | issues
        ]
      else
        issues
      end

    # Comma-separated aliases (should be 0 after backfill)
    # Skip long names — commas in company names (e.g., "GROUP, LLC") are not delimiters
    comma_aliases =
      from(a in InstrumentAlias,
        where: like(a.symbol, "%,%") and fragment("length(?)", a.symbol) <= 30,
        select: %{symbol: a.symbol, source: a.source}
      )
      |> Repo.all()

    if comma_aliases != [] do
      count = length(comma_aliases)

      [
        %{
          check: :comma_separated_aliases,
          severity: :warning,
          count: count,
          message: "#{count} aliases contain commas (should be split)",
          details: Enum.take(comma_aliases, 10)
        }
        | issues
      ]
    else
      issues
    end
  end
end
