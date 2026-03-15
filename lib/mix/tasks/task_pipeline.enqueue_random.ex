defmodule Mix.Tasks.TaskPipeline.EnqueueRandom do
  use Mix.Task

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Task

  @shortdoc "Creates a random task and enqueues its Oban job"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    attrs = %{
      title: "Random task #{System.unique_integer([:positive])}",
      type: Enum.random(Task.list_types()),
      priority: Enum.random(Task.list_priorities()),
      payload: %{"source" => "mix task_pipeline.enqueue_random"},
      max_attempts: 3
    }

    case Processing.create_task(attrs) do
      {:ok, %{task: task}} ->
        Mix.shell().info("Enqueued task #{task.id} with priority #{task.priority}")

      {:error, step, reason, _changes_so_far} ->
        Mix.raise("Failed to enqueue task at #{inspect(step)}: #{inspect(reason)}")
    end
  end
end
