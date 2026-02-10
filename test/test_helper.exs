# Start Playwright browser pool (skip in CI)
unless System.get_env("CI") do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end

Application.put_env(:phoenix_test, :base_url, DividendsomaticWeb.Endpoint.url())

# Exclude playwright and external tests by default
# Run with: mix test --include playwright --include external
ExUnit.configure(exclude: [playwright: true, external: true])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Dividendsomatic.Repo, :manual)
