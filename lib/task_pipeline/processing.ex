defmodule TaskPipeline.Processing do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task
  alias TaskPipeline.Repo
  alias TaskPipeline.Workers.TaskWorker

  # Task is created in queued state, job is inserted
  def create_task(attrs) do
    changeset = Task.changeset(%Task{}, attrs)

    Multi.new()
    |> Multi.insert(:task, changeset)
    |> Oban.insert(:job, fn %{task: task} ->
      TaskWorker.new(
        %{task_id: task.id},
        queue: task.priority,
        max_attempts: task.max_attempts
      )
    end)
    |> Repo.transaction()
  end

  # Transition: queued -> processing
  def claim_task(%Task{id: task_id}) do
    task_query(task_id, :queued)
    |> Repo.update_all(set: [status: :processing, updated_at: now()])
    |> handle_guarded_transition(:not_claimable)
  end

  # Transition: processing -> completed
  def task_completed(%Task{id: task_id}, result, %{attempt: attempt}) do
    %Result{message: message} = result

    task_transition_with_run(
      task_id,
      %{message: message, attempt: attempt},
      true,
      &complete_task/2
    )
  end

  # Transition: processing -> queued|failed (depending on attempts left)
  def task_failed(%Task{id: task_id}, result, meta) do
    %Result{message: message} = result
    %{attempt: attempt, max_attempts: max_attempts} = meta
    attrs = %{message: message, attempt: attempt}

    if attempt < max_attempts do
      task_transition_with_run(task_id, attrs, false, &retry_task/2)
    else
      task_transition_with_run(task_id, attrs, false, &fail_task/2)
    end
  end

  defp task_transition_with_run(task_id, attrs, success, transition_fun) do
    Multi.new()
    |> Multi.run(:task, fn repo, _changes -> transition_fun.(repo, task_id) end)
    |> Multi.insert(:run, fn %{task: task} -> Run.changeset(%Run{}, task.id, success, attrs) end)
    |> Repo.transaction()
  end

  defp complete_task(repo, task_id) do
    task_query(task_id, :processing)
    |> repo.update_all(set: [status: :completed, updated_at: now()])
    |> handle_guarded_transition(:not_completable)
  end

  defp retry_task(repo, task_id) do
    task_query(task_id, :processing)
    |> repo.update_all(set: [status: :queued, updated_at: now()])
    |> handle_guarded_transition(:not_retryable)
  end

  defp fail_task(repo, task_id) do
    task_query(task_id, :processing)
    |> repo.update_all(set: [status: :failed, updated_at: now()])
    |> handle_guarded_transition(:not_failable)
  end

  defp task_query(task_id, status) do
    Task
    |> where([task], task.id == ^task_id and task.status == ^status)
    |> select([task], task)
  end

  defp handle_guarded_transition({1, [task]}, _reason), do: {:ok, task}
  defp handle_guarded_transition({0, []}, reason), do: {:error, reason}

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
