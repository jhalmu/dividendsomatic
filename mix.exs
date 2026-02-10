defmodule Dividendsomatic.MixProject do
  use Mix.Project

  def project do
    [
      app: :dividendsomatic,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: elixirc_options(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: dialyzer(),
      test_coverage: [
        summary: [threshold: 60],
        ignore_modules: [
          DividendsomaticWeb.CoreComponents,
          DividendsomaticWeb.Gettext,
          DividendsomaticWeb.Layouts,
          DividendsomaticWeb.PageController,
          DividendsomaticWeb.PageHTML,
          DividendsomaticWeb.PlaywrightJsHelper,
          DividendsomaticWeb.Telemetry
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,
        :underspecs,
        :unknown
      ],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Compiler options
  defp elixirc_options(_), do: []

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Dividendsomatic.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.all": :test, "test.full": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.7.0"},
      {:ecto_sql, "~> 3.13.4"},
      {:postgrex, "~> 0.19"},
      {:phoenix_html, "~> 4.3.0"},
      {:phoenix_live_view, "~> 1.1.22"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.21.0"},
      {:req, "~> 0.5.17"},
      {:gettext, "~> 0.26.2"},
      {:jason, "~> 1.4.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.10.2"},

      # Project-specific
      {:nimble_csv, "~> 1.3.0"},
      {:oban, "~> 2.20.3"},
      {:contex, "~> 0.5.0"},
      {:timex, "~> 3.7.13"},

      # Monitoring and Telemetry
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:telemetry_metrics, "~> 1.1.0"},
      {:telemetry_poller, "~> 1.3.0"},

      # Dev and Test
      {:phoenix_test, "~> 0.9.1", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.10.1", only: :test, runtime: false},
      {:playwright_ex, "~> 0.3.2", only: :test, runtime: false},
      {:floki, "~> 0.38.0", only: :test},
      {:a11y_audit, "~> 0.3.1", only: :test, runtime: false},
      {:esbuild, "~> 0.10.0", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev},
      {:phoenix_live_reload, "~> 1.6.2", only: :dev},
      {:tailwind_formatter, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.16", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false},
      {:lazy_html, "~> 0.1.8", only: :test},
      {:tidewave, "~> 0.5.4", only: :dev},
      {:igniter, "~> 0.7", only: [:dev, :test]}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind dividendsomatic", "esbuild dividendsomatic"],
      "assets.deploy": [
        "tailwind dividendsomatic --minify",
        "esbuild dividendsomatic --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      "test.all": ["precommit", "credo --strict"],
      "test.full": ["test.all"]
    ]
  end
end
