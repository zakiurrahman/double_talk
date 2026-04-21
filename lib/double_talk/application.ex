defmodule DoubleTalk.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      repo_children() ++
        [
          DoubleTalkWeb.Telemetry,
          {DNSCluster, query: Application.get_env(:double_talk, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: DoubleTalk.PubSub},
          {Registry, keys: :unique, name: DoubleTalk.GameRooms.Registry},
          {DynamicSupervisor, name: DoubleTalk.GameRooms.RoomSupervisor, strategy: :one_for_one},
          DoubleTalkWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DoubleTalk.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DoubleTalkWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp repo_children do
    if Application.get_env(:double_talk, :start_repo, true) do
      [DoubleTalk.Repo]
    else
      []
    end
  end
end
