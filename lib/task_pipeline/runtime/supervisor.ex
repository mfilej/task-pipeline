defmodule TaskPipeline.Runtime.Supervisor do
  use Supervisor

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc false
  def child_specs do
    if Mix.env() != :test do
      [
        TaskPipeline.Runtime.Summary,
        TaskPipeline.Runtime.Metrics
      ]
    else
      []
    end
  end

  @impl true
  def init(_init_arg) do
    Supervisor.init(child_specs(), strategy: :one_for_one)
  end
end
