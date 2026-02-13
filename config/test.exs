import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dividendsomatic, Dividendsomatic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "dividendsomatic_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Oban testing mode - jobs run inline in tests
config :dividendsomatic, Oban, testing: :inline

# Disable market data providers in test — tests use Req.Test stubs directly
config :dividendsomatic, :market_data, providers: %{}

# Enable server for Playwright E2E tests
config :dividendsomatic, DividendsomaticWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "faB4RqtmmWrIgdU28uiMqQEPpLNuXb6KoRzfkOzevh5CQdBkBngawZRSHnB0J0om",
  server: true

# Enable SQL sandbox for E2E/Playwright tests
config :dividendsomatic, sql_sandbox: true

# In test we don't send emails
config :dividendsomatic, Dividendsomatic.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure phoenix_test with Playwright
config :phoenix_test,
  otp_app: :dividendsomatic,
  endpoint: DividendsomaticWeb.Endpoint,
  playwright: [
    browser: :chromium,
    browser_launch_timeout: 10_000,
    trace: System.get_env("PLAYWRIGHT_TRACE", "false") in ~w(t true),
    trace_dir: "tmp"
  ]
