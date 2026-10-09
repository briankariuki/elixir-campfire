defmodule Campfire.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Campfire.Hammer, [clean_period: 60000]},
      CampfireWeb.Telemetry,
      Campfire.Repo,
      {DNSCluster, query: Application.get_env(:campfire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Campfire.PubSub},
      Campfire.Presence,
      Campfire.AccountCache,
      CampfireWeb.MessageBody.Cache,
      # Encoded websocket diffs, see CampfireWeb.SocketSerializer. Entries are only useful for the
      # moments it takes every viewer to render the same message, so it is small.
      Supervisor.child_spec(
        {CampfireWeb.MessageBody.Cache, name: CampfireWeb.FrameCache, max_entries: 1_000},
        id: CampfireWeb.FrameCache
      ),
      # Whole messages rendered once for the viewers of a room, see CampfireWeb.MessageComponents.cached_message/1
      Supervisor.child_spec(
        {CampfireWeb.MessageBody.Cache, name: CampfireWeb.MessageHtmlCache, max_entries: 2_000},
        id: CampfireWeb.MessageHtmlCache
      ),
      # Background jobs: webhook delivery and ban cleanup (AshOban triggers). After PubSub,
      # because jobs broadcast.
      {Oban,
       AshOban.config(
         Application.fetch_env!(:campfire, :ash_domains),
         Application.fetch_env!(:campfire, Oban)
       )},
      # Start to serve requests, typically the last entry
      CampfireWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Campfire.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CampfireWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
