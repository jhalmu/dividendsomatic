defmodule Mix.Tasks.Validate.Data do
  @moduledoc """
  Run dividend data validation checks.

  ## Usage

      mix validate.data              # Run all validations
      mix validate.data --export     # Export timestamped snapshot + latest
      mix validate.data --compare    # Compare current vs latest snapshot
      mix validate.data --suggest    # Suggest threshold adjustments
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.DividendValidator
  alias Dividendsomatic.Portfolio.PortfolioValidator

  @shortdoc "Validate dividend data integrity"

  @export_dir "data_revisited"

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

    # Portfolio balance check (computed before export so it's available for serialization)
    portfolio_report = PortfolioValidator.validate()

    if "--export" in args, do: export_report(report, portfolio_report)
    if "--compare" in args, do: compare_with_latest(report)
    if "--suggest" in args, do: print_suggestions()

    print_portfolio_balance(portfolio_report)
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

  defp export_report(report, portfolio_report) do
    File.mkdir_p!(@export_dir)

    serialized = serialize_report(report)
    serialized = Map.put(serialized, :portfolio_balance, serialize_portfolio(portfolio_report))
    json = Jason.encode!(serialized, pretty: true)

    # Write timestamped file
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0, 15)
    timestamped_path = Path.join(@export_dir, "validation_#{timestamp}.json")
    File.write!(timestamped_path, json)

    # Overwrite latest
    latest_path = Path.join(@export_dir, "validation_latest.json")
    File.write!(latest_path, json)

    Mix.shell().info("\nExported to #{timestamped_path}")
    Mix.shell().info("Updated #{latest_path}")
  end

  defp compare_with_latest(current_report) do
    latest_path = Path.join(@export_dir, "validation_latest.json")

    case File.read(latest_path) do
      {:ok, contents} ->
        previous = Jason.decode!(contents)
        print_comparison(current_report, previous)

      {:error, :enoent} ->
        Mix.shell().info("\nNo previous snapshot found. Run --export first.")
    end
  end

  defp print_comparison(current, previous) do
    prev_count = previous["issue_count"]
    curr_count = current.issue_count
    prev_checked = previous["total_checked"]
    curr_checked = current.total_checked

    Mix.shell().info("\n=== Comparison vs Latest Snapshot ===")

    Mix.shell().info(
      "  Records:  #{prev_checked} → #{curr_checked} (#{diff_str(curr_checked - prev_checked)})"
    )

    Mix.shell().info(
      "  Issues:   #{prev_count} → #{curr_count} (#{diff_str(curr_count - prev_count)})"
    )

    prev_severity = previous["by_severity"] || %{}
    curr_severity = Map.new(current.by_severity, fn {k, v} -> {Atom.to_string(k), v} end)

    all_keys = Map.keys(prev_severity) ++ Map.keys(curr_severity)

    all_keys
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(fn key ->
      prev = Map.get(prev_severity, key, 0)
      curr = Map.get(curr_severity, key, 0)
      Mix.shell().info("    #{key}: #{prev} → #{curr} (#{diff_str(curr - prev)})")
    end)

    if previous["timestamp"] do
      Mix.shell().info("  Snapshot from: #{previous["timestamp"]}")
    end
  end

  defp diff_str(0), do: "no change"
  defp diff_str(n) when n > 0, do: "+#{n}"
  defp diff_str(n), do: "#{n}"

  defp print_suggestions do
    suggestions = DividendValidator.suggest_threshold_adjustments()

    if suggestions == [] do
      Mix.shell().info("\nNo threshold adjustments suggested.")
    else
      Mix.shell().info("\n=== Threshold Suggestions ===")

      Enum.each(suggestions, fn s ->
        Mix.shell().info(
          "  #{s.currency}: current=#{s.current_threshold}, suggested=#{s.suggested_threshold} (#{s.flagged_count} flags)"
        )
      end)
    end
  end

  defp print_portfolio_balance(%{checks: []}) do
    Mix.shell().info("\n=== Portfolio Balance Check ===")
    Mix.shell().info("  No portfolio data available.")
  end

  defp print_portfolio_balance(%{checks: checks}) do
    Mix.shell().info("\n=== Portfolio Balance Check ===")

    Enum.each(checks, fn check ->
      c = check.components

      if Map.get(c, :margin_mode) do
        Mix.shell().info("  Mode:             Margin account (NLV-based)")
      end

      Mix.shell().info("  Initial capital:  €#{format_decimal(c.initial_capital)}")
      Mix.shell().info("  + Cash deposits:  €#{format_decimal(c.total_deposits)}")
      Mix.shell().info("  - Withdrawals:    €#{format_decimal(c.total_withdrawals)}")
      Mix.shell().info("  = Net invested:   €#{format_decimal(c.net_invested)}")
      Mix.shell().info("  + Total return:   €#{format_decimal(c.total_return)}")
      Mix.shell().info("    (Realized P&L:   €#{format_decimal(c.realized_pnl)})")
      Mix.shell().info("    (Unrealized P&L: €#{format_decimal(c.unrealized_pnl)})")
      Mix.shell().info("    (Dividends:      €#{format_decimal(c.total_dividends)})")
      Mix.shell().info("    (Costs:         -€#{format_decimal(c.total_costs)})")

      if Map.has_key?(c, :interest_costs) do
        Mix.shell().info("      Interest:    -€#{format_decimal(c.interest_costs)}")
        Mix.shell().info("      Fees:        -€#{format_decimal(c.fee_costs)}")
      end

      Mix.shell().info("  = Expected value: €#{format_decimal(check.expected)}")

      if Map.has_key?(c, :position_value) do
        Mix.shell().info("  Position value:   €#{format_decimal(c.position_value)}")
        Mix.shell().info("  + Cash balance:   €#{format_decimal(c.cash_balance)}")
      end

      Mix.shell().info("  = Current value:  €#{format_decimal(check.actual)}")

      Mix.shell().info(
        "  Difference:       €#{format_decimal(check.difference)} (#{check.difference_pct}%)"
      )

      Mix.shell().info("  Status:           #{status_icon(check.status, c)}")
    end)
  end

  defp format_decimal(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp status_icon(:pass, c) do
    if Map.get(c, :margin_mode),
      do: "✓ PASS (within 5% tolerance, margin account)",
      else: "✓ PASS (within 1% tolerance)"
  end

  defp status_icon(:warning, c) do
    if Map.get(c, :margin_mode),
      do: "⚠ WARNING (5-20% difference, margin account)",
      else: "⚠ WARNING (1-5% difference)"
  end

  defp status_icon(:fail, c) do
    if Map.get(c, :margin_mode),
      do: "✗ FAIL (>20% difference, margin account)",
      else: "✗ FAIL (>5% difference)"
  end

  defp serialize_report(report) do
    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
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
  end

  defp serialize_portfolio(%{checks: checks, summary: summary}) do
    %{
      checks:
        Enum.map(checks, fn check ->
          %{
            name: Atom.to_string(check.name),
            status: Atom.to_string(check.status),
            expected: Decimal.to_string(check.expected),
            actual: Decimal.to_string(check.actual),
            difference: Decimal.to_string(check.difference),
            difference_pct: Decimal.to_string(check.difference_pct)
          }
        end),
      summary: summary
    }
  end
end
