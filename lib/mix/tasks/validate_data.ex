defmodule Mix.Tasks.Validate.Data do
  @moduledoc """
  Run dividend data validation checks.

  ## Usage

      mix validate.data              # Run all validations
      mix validate.data --export     # Export to data_revisited/validation_report.json
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.DividendValidator

  @shortdoc "Validate dividend data integrity"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    report = DividendValidator.validate()

    Mix.shell().info("=== Dividend Validation Report ===\n")
    Mix.shell().info("Total checked: #{report.total_checked}")
    Mix.shell().info("Issues found:  #{report.issue_count}")

    if report.by_severity != %{} do
      Mix.shell().info("\nBy severity:")

      Enum.each(report.by_severity, fn {severity, count} ->
        Mix.shell().info("  #{severity}: #{count}")
      end)
    end

    if report.issues != [] do
      Mix.shell().info("\nIssues:")

      report.issues
      |> Enum.group_by(& &1.type)
      |> Enum.each(&print_issue_group/1)
    else
      Mix.shell().info("\nNo issues found!")
    end

    if "--export" in args do
      export_report(report)
    end
  end

  defp print_issue_group({type, items}) do
    Mix.shell().info("\n  #{type} (#{length(items)}):")

    items
    |> Enum.take(10)
    |> Enum.each(fn issue ->
      symbol = Map.get(issue, :symbol, Map.get(issue, :isin, "?"))
      Mix.shell().info("    [#{issue.severity}] #{symbol}: #{issue.detail}")
    end)

    if length(items) > 10 do
      Mix.shell().info("    ... and #{length(items) - 10} more")
    end
  end

  defp export_report(report) do
    dir = "data_revisited"
    File.mkdir_p!(dir)

    serialized = %{
      total_checked: report.total_checked,
      issue_count: report.issue_count,
      by_severity: Map.new(report.by_severity, fn {k, v} -> {Atom.to_string(k), v} end),
      issues:
        Enum.map(report.issues, fn issue ->
          issue
          |> Map.update(:severity, nil, &Atom.to_string/1)
          |> Map.update(:type, nil, &Atom.to_string/1)
          |> Map.new(fn
            {:ex_date, d} when not is_nil(d) -> {:ex_date, Date.to_iso8601(d)}
            other -> other
          end)
        end)
    }

    json = Jason.encode!(serialized, pretty: true)
    path = Path.join(dir, "validation_report.json")
    File.write!(path, json)
    Mix.shell().info("\nExported validation report to #{path}")
  end
end
