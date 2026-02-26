defmodule Mix.Tasks.Lighthouse do
  @moduledoc """
  Runs Lighthouse audit against the local dev server.

  ## Usage

      mix lighthouse [--url URL] [--threshold SCORE] [--start-server]

  ## Options

    * `--url` - URL to audit (default: http://localhost:4000)
    * `--threshold` - Minimum performance score to pass (default: 50)
    * `--start-server` - Start the Phoenix server automatically (default: false)

  ## Requirements

    * Node.js and npx must be installed
    * Playwright's Chromium browser (run: npx playwright install chromium)

  ## Examples

      mix lighthouse
      mix lighthouse --start-server
      mix lighthouse --url http://localhost:4000/portfolio/2026-01-28
      mix lighthouse --threshold 70

  """
  use Mix.Task

  @shortdoc "Run Lighthouse audit on local server"

  @default_url "http://localhost:4000"
  @default_threshold 50

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [url: :string, threshold: :integer, start_server: :boolean],
        aliases: [u: :url, t: :threshold, s: :start_server]
      )

    url = Keyword.get(opts, :url, @default_url)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    start_server = Keyword.get(opts, :start_server, false)

    chrome_path = require_chrome_path()

    server_pid = maybe_start_server(start_server)

    try do
      ensure_server_ready(url)
      run_audit(url, chrome_path, threshold)
    after
      maybe_stop_server(server_pid)
    end
  end

  defp require_chrome_path do
    case find_chrome_path() do
      nil ->
        Mix.raise("""
        Chrome/Chromium not found. Please install Playwright's Chromium:

            npx playwright install chromium

        Or install Google Chrome.
        """)

      path ->
        path
    end
  end

  defp maybe_start_server(true) do
    Mix.shell().info("Starting Phoenix server...")
    Application.ensure_all_started(:dividendsomatic)
    :server_started
  end

  defp maybe_start_server(false), do: nil

  defp maybe_stop_server(nil), do: :ok

  defp maybe_stop_server(:server_started) do
    Mix.shell().info("Stopping Phoenix server...")
    Application.stop(:dividendsomatic)
  end

  defp ensure_server_ready(url) do
    unless wait_for_server(url, 30) do
      Mix.raise("""
      Server is not running at #{url}.

      Either start the server first with `mix phx.server`,
      or use the --start-server flag:

          mix lighthouse --start-server
      """)
    end
  end

  defp run_audit(url, chrome_path, threshold) do
    Mix.shell().info("Running Lighthouse audit on #{url}...")

    report_path = Path.join(File.cwd!(), "lighthouse-report")

    run_lighthouse_cmd(url, report_path, chrome_path)
    scores = parse_lighthouse_scores(report_path)
    display_scores(scores)
    check_threshold(scores, threshold)
  end

  defp run_lighthouse_cmd(url, report_path, chrome_path) do
    {output, exit_code} =
      System.cmd(
        "npx",
        [
          "lighthouse",
          url,
          "--output=json,html",
          "--output-path=#{report_path}",
          "--chrome-flags=--headless --no-sandbox --disable-gpu",
          "--only-categories=performance,accessibility,best-practices,seo",
          "--quiet"
        ],
        env: [{"CHROME_PATH", chrome_path}],
        stderr_to_stdout: true
      )

    if exit_code != 0 do
      Mix.shell().error("Lighthouse failed:")
      Mix.shell().error(output)
      Mix.raise("Lighthouse audit failed")
    end
  end

  defp parse_lighthouse_scores(report_path) do
    json_path = find_report_file(report_path)

    unless json_path do
      Mix.raise("Lighthouse report not found at #{report_path}")
    end

    categories = json_path |> File.read!() |> Jason.decode!() |> Map.fetch!("categories")

    %{
      performance: round(categories["performance"]["score"] * 100),
      accessibility: round(categories["accessibility"]["score"] * 100),
      best_practices: round(categories["best-practices"]["score"] * 100),
      seo: round(categories["seo"]["score"] * 100)
    }
  end

  defp find_report_file(report_path) do
    cond do
      File.exists?("#{report_path}.report.json") -> "#{report_path}.report.json"
      File.exists?(report_path) -> report_path
      true -> nil
    end
  end

  defp display_scores(scores) do
    Mix.shell().info("")
    Mix.shell().info("═══════════════════════════════════════")
    Mix.shell().info("        LIGHTHOUSE AUDIT RESULTS       ")
    Mix.shell().info("═══════════════════════════════════════")
    Mix.shell().info("")

    Enum.each(scores, fn {category, score} ->
      icon = score_icon(score)
      name = category |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
      Mix.shell().info("  #{icon} #{String.pad_trailing(name, 15)} #{score}")
    end)

    Mix.shell().info("")
  end

  defp score_icon(score) when score >= 90, do: "✅"
  defp score_icon(score) when score >= 50, do: "🟡"
  defp score_icon(_score), do: "❌"

  defp check_threshold(scores, threshold) do
    if scores.performance < threshold do
      Mix.raise("Performance score #{scores.performance} is below threshold #{threshold}")
    end

    Mix.shell().info("✅ All scores meet requirements (performance >= #{threshold})")
  end

  defp find_chrome_path do
    playwright_paths = [
      "~/Library/Caches/ms-playwright/chromium-*/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
      "~/Library/Caches/ms-playwright/chromium-*/chrome-mac/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
      "~/.cache/ms-playwright/chromium-*/chrome-linux/chrome"
    ]

    playwright_chrome =
      playwright_paths
      |> Enum.flat_map(&(Path.expand(&1) |> Path.wildcard()))
      |> Enum.find(&File.exists?/1)

    cond do
      playwright_chrome ->
        playwright_chrome

      File.exists?("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") ->
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

      System.find_executable("google-chrome") ->
        System.find_executable("google-chrome")

      System.find_executable("chromium") ->
        System.find_executable("chromium")

      System.find_executable("chromium-browser") ->
        System.find_executable("chromium-browser")

      true ->
        nil
    end
  end

  defp wait_for_server(url, timeout_seconds) do
    uri = URI.parse(url)
    host = String.to_charlist(uri.host || "localhost")
    port = uri.port || 4000

    Enum.any?(1..timeout_seconds, fn attempt ->
      try_connect(host, port, attempt < timeout_seconds)
    end)
  end

  defp try_connect(host, port, should_sleep) do
    case :gen_tcp.connect(host, port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        if should_sleep, do: Process.sleep(1000)
        false
    end
  end
end
