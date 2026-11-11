defmodule Tasktree.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Boot fails here if the workflow config is missing or malformed.
    Tasktree.Workflow.load!()
    Tasktree.Auth.load!()

    children = [
      TasktreeWeb.Telemetry,
      Tasktree.Repo,
      {DNSCluster, query: Application.get_env(:tasktree, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Tasktree.PubSub},
      # Start a worker by calling: Tasktree.Worker.start_link(arg)
      # {Tasktree.Worker, arg},
      # Start to serve requests, typically the last entry
      TasktreeWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tasktree.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TasktreeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
