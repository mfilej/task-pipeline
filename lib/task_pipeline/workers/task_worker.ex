defmodule TaskPipeline.Workers.TaskWorker do
  # Configure uniqueness so that the same task can't be re-enqueued as long as
  # Oban has a record of it. Could exclude :successful state depending on
  # desired behaviour.
  use Oban.Worker,
    unique: [
      fields: [:args, :worker],
      keys: [:task_id],
      period: :infinity,
      states: :all
    ]

  alias TaskPipeline.Processing.Handler
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Task

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}} = job) do
    case Processing.claim_task(%Task{id: task_id}) do
      {:ok, task} ->
        meta = Map.take(job, [:attempt, :max_attempts])

        case Handler.run(task) do
          {:ok, %Result{} = result} ->
            {:ok, _} = Processing.task_completed(task, result, meta)

            :ok

          {:error, %Result{} = result} ->
            {:ok, _} = Processing.task_failed(task, result, meta)

            {:error, result.message}
        end

      {:error, :not_claimable} ->
        # The task has already been claimed by another worker (or job is stale).

        :ok

        # Arguably, here we could've decided to return:
        # {:cancel, reason}
    end
  end
end
