defmodule Mix.Tasks.Check.All do
  @moduledoc """
  Run all data integrity checks in one pass.

  Combines dividend validation, data gap analysis, and schema integrity checks.

  ## Usage

      mix check.all
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.{DataGapAnalyzer, DividendValidator, SchemaIntegrity}

  @shortdoc "Run all data integrity checks"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("=== Data Integrity Check ===\n")

    # 1. Dividend validation
    validation = DividendValidator.validate()

    Mix.shell().info("Dividend Validation:")
    Mix.shell().info("  Checked: #{validation.total_checked}")
    Mix.shell().info("  Issues:  #{validation.issue_count}")

    Enum.each(validation.by_severity, fn {severity, count} ->
      Mix.shell().info("    #{severity}: #{count}")
    end)

    # 2. Gap analysis
    gap_report = DataGapAnalyzer.analyze()
    s = gap_report.summary

    Mix.shell().info("\nData Gap Analysis:")
    Mix.shell().info("  Dividends:    #{s.dividend_count}")
    Mix.shell().info("  Snapshots:    #{s.snapshot_count}")
    Mix.shell().info("  Snapshot gaps: #{length(gap_report.snapshot_gaps)}")
    Mix.shell().info("  Dividend gaps: #{length(gap_report.dividend_gaps)}")

    # 3. Schema integrity
    integrity = SchemaIntegrity.check_all()

    Mix.shell().info("\nSchema Integrity:")
    Mix.shell().info("  Checks run: #{integrity.total_checks}")
    Mix.shell().info("  Issues:     #{integrity.total_issues}")

    Enum.each(integrity.by_severity, fn {severity, count} ->
      Mix.shell().info("    #{severity}: #{count}")
    end)

    if integrity.total_issues > 0 do
      Mix.shell().info("\n  Details:")

      Enum.each(integrity.issues, fn issue ->
        icon = severity_icon(issue.severity)
        Mix.shell().info("    #{icon} #{issue.message}")
      end)
    end

    # Combined summary
    total_issues =
      validation.issue_count +
        length(gap_report.snapshot_gaps) +
        length(gap_report.dividend_gaps) +
        integrity.total_issues

    Mix.shell().info("\n--- Summary ---")

    if total_issues == 0 do
      Mix.shell().info("All checks passed.")
    else
      Mix.shell().info("Total findings: #{total_issues}")
      Mix.shell().info("Run `mix validate.data` or `mix report.gaps` for details.")
    end
  end

  defp severity_icon(:error), do: "[ERROR]"
  defp severity_icon(:warning), do: "[WARN]"
  defp severity_icon(:info), do: "[INFO]"
  defp severity_icon(_), do: "[?]"
end
