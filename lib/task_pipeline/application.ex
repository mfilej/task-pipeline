defmodule TaskPipeline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TaskPipeline.Supervisor]
    Supervisor.start_link(child_specs(), opts)
  end

  @doc false
  def child_specs do
    # NOTE: Runtime.Supervisor must start before Oban so event subscribers are
    # ready before jobs publish updates.
    [
      TaskPipelineWeb.Telemetry,
      TaskPipeline.Repo,
      {DNSCluster, query: Application.get_env(:task_pipeline, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TaskPipeline.PubSub},
      TaskPipeline.Runtime.Supervisor,
      {Oban, Application.fetch_env!(:task_pipeline, Oban)},
      TaskPipelineWeb.Endpoint
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TaskPipelineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
