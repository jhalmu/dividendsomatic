defmodule Mix.Tasks.Check.Integrity do
  @moduledoc """
  Run integrity checks against an IBKR Flex Actions.csv file.

  Cross-checks dividends, trades, and ISINs between Actions.csv and the database.

  ## Usage

      mix check.integrity path/to/Actions.csv
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.IntegrityChecker

  @shortdoc "Check data integrity against IBKR Actions.csv"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [path] ->
        run_checks(path)

      _ ->
        Mix.shell().error("Usage: mix check.integrity path/to/Actions.csv")
    end
  end

  defp run_checks(path) do
    Mix.shell().info("Running integrity checks against #{path}...\n")

    case IntegrityChecker.run_all(path) do
      {:ok, checks} ->
        Enum.each(checks, &print_check/1)
        print_summary(checks)

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end

  defp print_check(check) do
    status_icon =
      case check.status do
        :pass -> "PASS"
        :fail -> "FAIL"
        :warn -> "WARN"
      end

    Mix.shell().info("[#{status_icon}] #{check.name}")
    Mix.shell().info("  #{check.message}")

    if check.details != [] do
      Mix.shell().info("  Details:")

      check.details
      |> Enum.take(20)
      |> Enum.each(fn detail ->
        Mix.shell().info("    - #{detail}")
      end)

      remaining = length(check.details) - 20

      if remaining > 0 do
        Mix.shell().info("    ... and #{remaining} more")
      end
    end

    Mix.shell().info("")
  end

  defp print_summary(checks) do
    pass = Enum.count(checks, &(&1.status == :pass))
    fail = Enum.count(checks, &(&1.status == :fail))
    warn = Enum.count(checks, &(&1.status == :warn))

    Mix.shell().info("---")
    Mix.shell().info("Summary: #{pass} PASS, #{warn} WARN, #{fail} FAIL")
  end
end
