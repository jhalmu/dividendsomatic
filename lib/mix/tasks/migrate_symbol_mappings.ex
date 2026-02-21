defmodule Mix.Tasks.Migrate.SymbolMappings do
  @shortdoc "Migrate resolved legacy_symbol_mappings to instrument_aliases"
  @moduledoc """
  One-time migration: copies resolved symbol mappings to instrument_aliases,
  then reports results. Run before dropping legacy_symbol_mappings table.

  ## Usage

      mix migrate.symbol_mappings
      mix migrate.symbol_mappings --dry-run
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args

    IO.puts(
      if dry_run?,
        do: "\n=== DRY RUN: Symbol Mapping Migration ===",
        else: "\n=== Symbol Mapping Migration ==="
    )

    resolved =
      Repo.all(
        from(sm in "legacy_symbol_mappings",
          where: sm.status == "resolved",
          select: %{
            isin: sm.isin,
            finnhub_symbol: sm.finnhub_symbol,
            exchange: sm.exchange,
            security_name: sm.security_name
          }
        )
      )

    IO.puts("Found #{length(resolved)} resolved mappings")

    results =
      Enum.reduce(resolved, %{migrated: 0, skipped: 0, no_instrument: 0}, fn mapping, acc ->
        case Repo.get_by(Instrument, isin: mapping.isin) do
          nil ->
            IO.puts("  SKIP (no instrument): #{mapping.isin} -> #{mapping.finnhub_symbol}")
            %{acc | no_instrument: acc.no_instrument + 1}

          instrument ->
            # Extract exchange from finnhub symbol (e.g., "KESKOB.HE" -> "HE")
            exchange = extract_exchange(mapping.finnhub_symbol, mapping.exchange)
            symbol = extract_symbol(mapping.finnhub_symbol)

            existing =
              Repo.one(
                from(a in InstrumentAlias,
                  where: a.instrument_id == ^instrument.id and a.symbol == ^symbol,
                  where:
                    ^if(exchange,
                      do: dynamic([a], a.exchange == ^exchange),
                      else: dynamic([a], is_nil(a.exchange))
                    ),
                  limit: 1
                )
              )

            if existing do
              %{acc | skipped: acc.skipped + 1}
            else
              if dry_run? do
                IO.puts("  WOULD CREATE: #{instrument.isin} -> #{symbol} (#{exchange})")
                %{acc | migrated: acc.migrated + 1}
              else
                changeset =
                  InstrumentAlias.changeset(%InstrumentAlias{}, %{
                    instrument_id: instrument.id,
                    symbol: symbol,
                    exchange: exchange,
                    source: "symbol_mapping"
                  })

                case Repo.insert(changeset) do
                  {:ok, _} ->
                    %{acc | migrated: acc.migrated + 1}

                  {:error, cs} ->
                    IO.puts("  ERROR: #{mapping.isin} -> #{inspect(cs.errors)}")
                    %{acc | skipped: acc.skipped + 1}
                end
              end
            end
        end
      end)

    unmappable_count =
      Repo.one(
        from(sm in "legacy_symbol_mappings",
          where: sm.status == "unmappable",
          select: count()
        )
      )

    IO.puts("\n--- Results ---")
    IO.puts("  Migrated:       #{results.migrated}")
    IO.puts("  Skipped (dup):  #{results.skipped}")
    IO.puts("  No instrument:  #{results.no_instrument}")
    IO.puts("  Unmappable:     #{unmappable_count} (skipped by design)")

    IO.puts(
      "  Total:          #{results.migrated + results.skipped + results.no_instrument + unmappable_count}"
    )

    unless dry_run? do
      IO.puts("\nMigration complete. Safe to drop legacy_symbol_mappings table.")
    end
  end

  # "KESKOB.HE" -> "HE", nil -> nil
  defp extract_exchange(finnhub_symbol, fallback) do
    case String.split(finnhub_symbol || "", ".") do
      [_, exchange] -> exchange
      _ -> fallback
    end
  end

  # "KESKOB.HE" -> "KESKOB"
  defp extract_symbol(finnhub_symbol) do
    finnhub_symbol
    |> String.split(".")
    |> List.first()
  end
end
