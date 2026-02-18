defmodule Mix.Tasks.Check.All do
  @moduledoc """
  Run all data integrity checks in one pass.

  Combines dividend validation and data gap analysis into a single summary.

  ## Usage

      mix check.all
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.{DataGapAnalyzer, DividendValidator}

  @shortdoc "Run all data integrity checks"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("=== Data Integrity Check ===\n")

    # Dividend validation
    validation = DividendValidator.validate()

    Mix.shell().info("Dividend Validation:")
    Mix.shell().info("  Checked: #{validation.total_checked}")
    Mix.shell().info("  Issues:  #{validation.issue_count}")

    Enum.each(validation.by_severity, fn {severity, count} ->
      Mix.shell().info("    #{severity}: #{count}")
    end)

    # Gap analysis
    gap_report = DataGapAnalyzer.analyze()
    s = gap_report.summary

    Mix.shell().info("\nData Gap Analysis:")
    Mix.shell().info("  Dividends:    #{s.dividend_count}")
    Mix.shell().info("  Snapshots:    #{s.snapshot_count}")
    Mix.shell().info("  Snapshot gaps: #{length(gap_report.snapshot_gaps)}")
    Mix.shell().info("  Dividend gaps: #{length(gap_report.dividend_gaps)}")

    # Combined summary
    total_issues =
      validation.issue_count + length(gap_report.snapshot_gaps) + length(gap_report.dividend_gaps)

    Mix.shell().info("\n--- Summary ---")

    if total_issues == 0 do
      Mix.shell().info("All checks passed.")
    else
      Mix.shell().info("Total findings: #{total_issues}")
      Mix.shell().info("Run `mix validate.data` or `mix report.gaps` for details.")
    end
  end
end
