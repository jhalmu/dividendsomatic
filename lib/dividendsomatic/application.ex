defmodule Dividendsomatic.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DividendsomaticWeb.Telemetry,
      Dividendsomatic.Repo,
      {DNSCluster, query: Application.get_env(:dividendsomatic, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dividendsomatic.PubSub},
      {Oban, Application.fetch_env!(:dividendsomatic, Oban)},
      # Start to serve requests, typically the last entry
      DividendsomaticWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dividendsomatic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DividendsomaticWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
