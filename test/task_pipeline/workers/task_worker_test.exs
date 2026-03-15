defmodule TaskPipeline.Workers.TaskWorkerTest do
  use TaskPipeline.DataCase, async: false
  use Oban.Testing, repo: TaskPipeline.Repo

  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Task
  alias TaskPipeline.Workers.TaskWorker

  test "perform/1 completes the task and records a successful run" do
    task =
      Repo.insert!(%Task{
        title: "Worker task",
        type: :import,
        priority: :critical,
        payload: %{"id" => 42},
        max_attempts: 3,
        status: :queued
      })

    assert :ok = perform_job(TaskWorker, %{task_id: task.id}, attempt: 1)

    persisted_task = Repo.get!(Task, task.id)
    run = Repo.get_by!(Run, task_id: task.id)

    assert persisted_task.status == :completed
    assert run.attempt == 1
    assert run.success
    assert run.message =~ "Success in "
  end

  test "perform/1 retries the task and records a failed run" do
    put_handler_failure_rate(1.0)

    task =
      Repo.insert!(%Task{
        title: "Worker retry task",
        type: :import,
        priority: :critical,
        payload: %{"id" => 43},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, message} = perform_job(TaskWorker, %{task_id: task.id}, attempt: 1)

    persisted_task = Repo.get!(Task, task.id)
    run = Repo.get_by!(Run, task_id: task.id)

    assert persisted_task.status == :queued
    assert run.attempt == 1
    refute run.success
    assert message =~ "Failure in "
    assert run.message =~ "Failure in "
  end

  test "perform/1 fails the task after the last attempt and records a failed run" do
    put_handler_failure_rate(1.0)

    task =
      Repo.insert!(%Task{
        title: "Worker failed task",
        type: :import,
        priority: :critical,
        payload: %{"id" => 44},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, message} =
             perform_job(TaskWorker, %{task_id: task.id}, attempt: 3, max_attempts: 3)

    persisted_task = Repo.get!(Task, task.id)
    run = Repo.get_by!(Run, task_id: task.id)

    assert persisted_task.status == :failed
    assert run.attempt == 3
    refute run.success
    assert message =~ "Failure in "
    assert run.message =~ "Failure in "
  end
end
