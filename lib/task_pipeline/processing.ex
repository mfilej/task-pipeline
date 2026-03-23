defmodule TaskPipeline.Processing do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TaskPipeline.Processing.Events
  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task
  alias TaskPipeline.Repo
  alias TaskPipeline.Workers.TaskWorker

  def tasks_summary do
    counts =
      Task
      |> group_by([t], t.status)
      |> select([t], {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    Task.list_statuses()
    |> Map.from_keys(0)
    |> Map.merge(counts)
  end

  def list_tasks(params) do
    Flop.validate_and_run(Task, params, for: Task)
  end

  def get_task!(id) do
    Task
    |> Repo.get!(id)
    |> Repo.preload(runs: task_runs_query())
  end

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
    |> publish_transition(&Events.task_created/1)
  end

  # Transition: queued -> processing
  def claim_task(%Task{id: task_id}) do
    task_query(task_id, :queued)
    |> Repo.update_all(set: [status: :processing, updated_at: now()])
    |> handle_guarded_transition(:not_claimable)
    |> wrap_task_result()
    |> publish_transition(&Events.task_claimed/1)
  end

  # Transition: processing -> completed
  def task_completed(%Task{id: task_id}, result, %{attempt: attempt}) do
    %Result{message: message} = result
    attrs = %{message: message, attempt: attempt}

    task_transition_with_run(task_id, attrs, true, &complete_task/2)
    |> publish_transition(&Events.task_completed(Map.put(&1, :result, result)))
  end

  # Transition: processing -> queued|failed (depending on attempts left)
  def task_failed(%Task{id: task_id}, result, meta) do
    %Result{message: message} = result
    %{attempt: attempt, max_attempts: max_attempts} = meta
    attrs = %{message: message, attempt: attempt}

    if attempt < max_attempts do
      task_transition_with_run(task_id, attrs, false, &retry_task/2)
      |> publish_transition(&Events.task_retried(Map.merge(&1, %{result: result, meta: meta})))
    else
      task_transition_with_run(task_id, attrs, false, &fail_task/2)
      |> publish_transition(&Events.task_failed(Map.merge(&1, %{result: result, meta: meta})))
    end
  end

  defp task_transition_with_run(task_id, attrs, success, transition_fun) do
    Multi.new()
    |> Multi.run(:task, fn repo, _changes -> transition_fun.(repo, task_id) end)
    |> Multi.insert(:run, fn %{task: task} -> Run.changeset(%Run{}, task.id, success, attrs) end)
    |> Repo.transaction()
  end

  defp publish_transition({:ok, payload} = result, publisher) do
    :ok = publisher.(payload)
    result
  end

  defp publish_transition(result, _publisher) do
    result
  end

  defp wrap_task_result({:ok, %Task{} = task}) do
    {:ok, %{task: task}}
  end

  defp wrap_task_result(result) do
    result
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

  defp task_runs_query do
    from(r in Run, order_by: [asc: r.attempt])
  end
end
