# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dividendsomatic,
  ecto_repos: [Dividendsomatic.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :dividendsomatic, DividendsomaticWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DividendsomaticWeb.ErrorHTML, json: DividendsomaticWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dividendsomatic.PubSub,
  live_view: [signing_salt: "s1EiNisZ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :dividendsomatic, Dividendsomatic.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  dividendsomatic: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  dividendsomatic: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban
config :dividendsomatic, Oban,
  repo: Dividendsomatic.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"00 10 * * 1-5", Dividendsomatic.Workers.DataImportWorker,
        args: %{"source" => "csv_directory"}}
     ]}
  ],
  queues: [default: 10, gmail_import: 1, data_import: 1]

# Multi-provider market data configuration
config :dividendsomatic, :market_data,
  providers: %{
    quote: [
      Dividendsomatic.MarketData.Providers.Finnhub,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    candles: [
      Dividendsomatic.MarketData.Providers.YahooFinance,
      Dividendsomatic.MarketData.Providers.Eodhd,
      Dividendsomatic.MarketData.Providers.Finnhub
    ],
    forex: [
      Dividendsomatic.MarketData.Providers.YahooFinance,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    profile: [
      Dividendsomatic.MarketData.Providers.Finnhub,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    metrics: [
      Dividendsomatic.MarketData.Providers.Finnhub
    ],
    isin_lookup: [
      Dividendsomatic.MarketData.Providers.Finnhub
    ]
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
