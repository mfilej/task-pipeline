defmodule TaskPipeline.ProcessingTest do
  use TaskPipeline.DataCase, async: true
  use Oban.Testing, repo: TaskPipeline.Repo

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task
  alias TaskPipeline.Workers.TaskWorker

  describe "get_task!/1" do
    test "returns a task with preloaded runs ordered by attempt" do
      task =
        Repo.insert!(%Task{
          title: "Fetch me",
          type: :import,
          priority: :normal,
          payload: %{},
          max_attempts: 3,
          status: :completed
        })

      Repo.insert!(%Run{task_id: task.id, attempt: 2, success: true, message: "second"})
      Repo.insert!(%Run{task_id: task.id, attempt: 1, success: false, message: "first"})

      fetched = Processing.get_task!(task.id)
      assert fetched.id == task.id
      assert [run1, run2] = fetched.runs
      assert run1.attempt == 1
      assert run2.attempt == 2
    end

  test "create_task/1 creates a queued task and enqueues its job" do
    attrs = %{
      title: "Process me",
      type: :import,
      priority: :high,
      payload: %{"source" => "test"}
    }

    assert {:ok, %{task: queued_task, job: job}} = Processing.create_task(attrs)

    assert_enqueued worker: TaskWorker, args: %{"task_id" => queued_task.id}, queue: "high"
    assert job.state == "available"
    assert job.queue == "high"
    assert job.max_attempts == 3
    assert queued_task.status == :queued

    persisted_task = Repo.get!(Task, queued_task.id)

    assert persisted_task.status == :queued
    assert persisted_task.payload == %{"source" => "test"}
    assert persisted_task.max_attempts == 3
  end

  test "claim_task/1 transitions a queued task to processing" do
    task =
      Repo.insert!(%Task{
        title: "Claim me",
        type: :import,
        priority: :normal,
        payload: %{},
        max_attempts: 3,
        status: :queued
      })

    assert {:ok, _claimed_task} = Processing.claim_task(task)

    persisted_task = Repo.get!(Task, task.id)

    assert persisted_task.status == :processing
  end

  test "claim_task/1 rejects tasks that are not queued" do
    task =
      Repo.insert!(%Task{
        title: "Already processing",
        type: :report,
        priority: :high,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:error, :not_claimable} = Processing.claim_task(task)
    assert Repo.get!(Task, task.id).status == :processing
  end

  test "task_failed/3 retries when attempts remain" do
    task =
      Repo.insert!(%Task{
        title: "Retry via task_failed",
        type: :report,
        priority: :high,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: retried_task, run: run}} =
             Processing.task_failed(task, %Result{duration: 0, message: "fail"}, %{
               attempt: 1,
               max_attempts: 3
             })

    assert retried_task.status == :queued
    assert run.task_id == task.id
    assert run.attempt == 1
    refute run.success
    assert run.message == "fail"
    assert Repo.get!(Task, task.id).status == :queued
  end

  test "task_failed/3 returns :not_retryable when the claim can't be obtained" do
    task =
      Repo.insert!(%Task{
        title: "Not retryable via task_failed",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, :task, :not_retryable, %{}} =
             Processing.task_failed(task, %Result{duration: 0, message: "fail"}, %{
               attempt: 1,
               max_attempts: 3
             })

    assert Repo.get!(Task, task.id).status == :queued
    assert Repo.get_by(Run, task_id: task.id) == nil
  end

  test "task_failed/3 fails when attempts are exhausted" do
    task =
      Repo.insert!(%Task{
        title: "Fail via task_failed",
        type: :cleanup,
        priority: :critical,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: failed_task, run: run}} =
             Processing.task_failed(
               task,
               %Result{duration: 0, message: "terminal fail"},
               %{attempt: 3, max_attempts: 3}
             )

    assert failed_task.status == :failed
    assert run.task_id == task.id
    assert run.attempt == 3
    refute run.success
    assert run.message == "terminal fail"
    assert Repo.get!(Task, task.id).status == :failed
  end

  test "task_failed/3 returns :not_failable when the claim can't be obtained" do
    task =
      Repo.insert!(%Task{
        title: "Not failable via task_failed",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, :task, :not_failable, %{}} =
             Processing.task_failed(task, %Result{duration: 0, message: "terminal fail"}, %{
               attempt: 3,
               max_attempts: 3
             })

    assert Repo.get!(Task, task.id).status == :queued
    assert Repo.get_by(Run, task_id: task.id) == nil
  end

  test "task_completed/3 completes a task and records a successful run" do
    task =
      Repo.insert!(%Task{
        title: "Complete with run",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: completed_task, run: run}} =
             Processing.task_completed(task, %Result{duration: 0, message: "done"}, %{
               attempt: 1
             })

    assert completed_task.status == :completed
    assert run.task_id == task.id
    assert run.attempt == 1
    assert run.success
    assert run.message == "done"
    assert Repo.get!(Task, task.id).status == :completed
  end

  test "task_completed/3 returns :not_completable when the claim can't be obtained" do
    task =
      Repo.insert!(%Task{
        title: "Not completable",
        type: :export,
        priority: :normal,
        payload: %{},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, :task, :not_completable, %{}} =
             Processing.task_completed(task, %Result{duration: 0, message: "done"}, %{
               attempt: 1
             })

    assert Repo.get!(Task, task.id).status == :queued
    assert Repo.get_by(Run, task_id: task.id) == nil
  end
end
