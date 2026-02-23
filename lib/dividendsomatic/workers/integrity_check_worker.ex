defmodule Dividendsomatic.Workers.IntegrityCheckWorker do
  @moduledoc """
  Oban worker that runs daily schema integrity checks.

  Runs the same checks as `mix check.all` and logs warnings
  if issues are found or if issue count increases.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  alias Dividendsomatic.Portfolio.SchemaIntegrity

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("IntegrityCheckWorker: starting daily integrity checks")

    result = SchemaIntegrity.check_all()

    if result.total_issues == 0 do
      Logger.info("IntegrityCheckWorker: all checks passed (0 issues)")
    else
      log_integrity_summary(result)
      Enum.each(result.issues, &log_issue/1)
    end

    :ok
  end

  defp log_integrity_summary(result) do
    Logger.warning(
      "IntegrityCheckWorker: #{result.total_issues} issues found — " <>
        "#{Map.get(result.by_severity, :error, 0)} errors, " <>
        "#{Map.get(result.by_severity, :warning, 0)} warnings, " <>
        "#{Map.get(result.by_severity, :info, 0)} info"
    )
  end

  defp log_issue(issue) do
    level = if issue.severity == :error, do: :warning, else: :info
    Logger.log(level, "  [#{issue.severity}] #{issue.message}")
  end
end
