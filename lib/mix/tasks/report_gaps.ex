defmodule Mix.Tasks.Report.Gaps do
  @moduledoc """
  Generate a data gap analysis report.

  ## Usage

      mix report.gaps                  # Print report to console
      mix report.gaps --format=markdown  # Output as markdown
      mix report.gaps --year=2023      # Filter to specific year
      mix report.gaps --export         # Export to data_revisited/gap_report.json
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.DataGapAnalyzer

  @shortdoc "Generate data gap analysis report"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    report = DataGapAnalyzer.analyze()

    if opts[:export] do
      export_report(report)
    end

    if opts[:format] == "markdown" do
      print_markdown(report, opts)
    else
      print_report(report, opts)
    end
  end

  defp parse_args(args) do
    args
    |> Enum.reduce(%{}, fn arg, acc ->
      cond do
        String.starts_with?(arg, "--format=") ->
          Map.put(acc, :format, String.replace_prefix(arg, "--format=", ""))

        String.starts_with?(arg, "--year=") ->
          year = arg |> String.replace_prefix("--year=", "") |> String.to_integer()
          Map.put(acc, :year, year)

        arg == "--export" ->
          Map.put(acc, :export, true)

        true ->
          acc
      end
    end)
  end

  defp print_report(report, opts) do
    Mix.shell().info("=== Data Gap Analysis Report ===\n")

    # Summary
    s = report.summary
    Mix.shell().info("Database Summary:")
    Mix.shell().info("  Dividends:     #{s.dividend_count}")
    Mix.shell().info("  Snapshots:     #{s.snapshot_count}")
    Mix.shell().info("  Transactions:  #{s.transaction_count}")

    if s.dividend_range do
      Mix.shell().info("  Dividend range: #{s.dividend_range.min} → #{s.dividend_range.max}")
    end

    if s.snapshot_range do
      Mix.shell().info("  Snapshot range: #{s.snapshot_range.min} → #{s.snapshot_range.max}")
    end

    # 364-day chunks
    Mix.shell().info("\n=== 364-Day Chunks ===")

    chunks = filter_by_year(report.chunks, opts)

    Enum.each(chunks, fn chunk ->
      Mix.shell().info("\n  #{chunk.from} → #{chunk.to} (#{chunk.calendar_days}d)")

      Mix.shell().info(
        "    Snapshots: #{chunk.snapshot_count}/#{chunk.expected_trading_days} (#{chunk.coverage_pct}%)"
      )

      Mix.shell().info("    Dividends: #{chunk.dividend_count}")
      Mix.shell().info("    Transactions: #{chunk.transaction_count}")

      if chunk.sources != [] do
        Mix.shell().info("    Sources: #{Enum.join(chunk.sources, ", ")}")
      end
    end)

    # Dividend gaps
    if report.dividend_gaps != [] do
      Mix.shell().info("\n=== Dividend Gaps (>400 days) ===")

      Enum.each(report.dividend_gaps, &print_dividend_gap/1)
    end

    # Snapshot gaps
    if report.snapshot_gaps != [] do
      Mix.shell().info("\n=== Snapshot Gaps (>7 days) ===")

      report.snapshot_gaps
      |> Enum.take(20)
      |> Enum.each(fn gap ->
        Mix.shell().info("  #{gap.from} → #{gap.to} (#{gap.days} days)")
      end)

      if length(report.snapshot_gaps) > 20 do
        Mix.shell().info("  ... and #{length(report.snapshot_gaps) - 20} more")
      end
    end
  end

  defp print_dividend_gap(dg) do
    Mix.shell().info("\n  #{dg.symbol} (#{dg.count} dividends, #{dg.first}→#{dg.last})")

    Enum.each(dg.gaps, fn gap ->
      Mix.shell().info("    GAP: #{gap.from} → #{gap.to} (#{gap.days} days)")
    end)
  end

  defp print_markdown(report, opts) do
    s = report.summary
    Mix.shell().info("# Data Gap Analysis Report\n")
    Mix.shell().info("## Summary\n")
    Mix.shell().info("| Metric | Count |")
    Mix.shell().info("|--------|-------|")
    Mix.shell().info("| Dividends | #{s.dividend_count} |")
    Mix.shell().info("| Snapshots | #{s.snapshot_count} |")
    Mix.shell().info("| Transactions | #{s.transaction_count} |")

    Mix.shell().info("\n## 364-Day Chunks\n")
    Mix.shell().info("| Period | Snapshots | Coverage | Dividends | Txns |")
    Mix.shell().info("|--------|-----------|----------|-----------|------|")

    chunks = filter_by_year(report.chunks, opts)

    Enum.each(chunks, fn c ->
      Mix.shell().info(
        "| #{c.from}→#{c.to} | #{c.snapshot_count}/#{c.expected_trading_days} | #{c.coverage_pct}% | #{c.dividend_count} | #{c.transaction_count} |"
      )
    end)
  end

  defp filter_by_year(chunks, %{year: year}) do
    year_start = Date.new!(year, 1, 1)
    year_end = Date.new!(year, 12, 31)

    Enum.filter(chunks, fn c ->
      Date.compare(c.to, year_start) != :lt and Date.compare(c.from, year_end) != :gt
    end)
  end

  defp filter_by_year(chunks, _), do: chunks

  defp export_report(report) do
    dir = "data_revisited"
    File.mkdir_p!(dir)

    json = Jason.encode!(serialize_report(report), pretty: true)
    path = Path.join(dir, "gap_report.json")
    File.write!(path, json)
    Mix.shell().info("Exported gap report to #{path}")
  end

  defp serialize_report(report) do
    %{
      summary: report.summary,
      chunks:
        Enum.map(report.chunks, fn c ->
          Map.update!(c, :from, &Date.to_iso8601/1) |> Map.update!(:to, &Date.to_iso8601/1)
        end),
      dividend_gaps:
        Enum.map(report.dividend_gaps, fn dg ->
          %{
            symbol: dg.symbol,
            key: dg.key,
            count: dg.count,
            first: Date.to_iso8601(dg.first),
            last: Date.to_iso8601(dg.last),
            gaps:
              Enum.map(dg.gaps, fn g ->
                %{from: Date.to_iso8601(g.from), to: Date.to_iso8601(g.to), days: g.days}
              end)
          }
        end),
      snapshot_gap_count: length(report.snapshot_gaps)
    }
  end
end
