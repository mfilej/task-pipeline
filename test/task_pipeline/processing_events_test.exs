defmodule TaskPipeline.ProcessingEventsTest do
  use TaskPipeline.DataCase, async: false
  use Oban.Testing, repo: TaskPipeline.Repo

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Events
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Task

  setup do
    :ok = Events.subscribe()
    :ok
  end

  test "create_task/1 emits task_created after the transaction commits" do
    attrs = %{
      title: "Emit create",
      type: :import,
      priority: :high,
      payload: %{"source" => "test"}
    }

    assert {:ok, %{task: task}} = Processing.create_task(attrs)

    assert_receive {:task_created, %{task_id: task_id, from_status: nil, to_status: :queued}}

    assert task_id == task.id
  end

  test "claim_task/1 emits task_claimed on success" do
    task =
      Repo.insert!(%Task{
        title: "Emit claim",
        type: :report,
        priority: :normal,
        payload: %{},
        status: :queued
      })

    assert {:ok, %{task: %Task{id: task_id}}} = Processing.claim_task(task)

    assert_receive {:task_claimed,
                    %{task_id: ^task_id, from_status: :queued, to_status: :processing}}
  end

  test "claim_task/1 does not emit an event when the transition is rejected" do
    task =
      Repo.insert!(%Task{
        title: "Rejected claim",
        type: :report,
        priority: :normal,
        payload: %{},
        status: :processing
      })

    task_id = task.id

    assert {:error, :not_claimable} = Processing.claim_task(task)

    refute_receive {:task_claimed, %{task_id: ^task_id}}
  end

  test "task_completed/3 emits task_completed after persisting the run" do
    task =
      Repo.insert!(%Task{
        title: "Emit completion",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: %Task{id: task_id}, run: %Run{attempt: 2}}} =
             Processing.task_completed(task, %Result{duration: 150, message: "done"}, %{
               attempt: 2
             })

    assert_receive {:task_completed,
                    %{
                      task_id: ^task_id,
                      from_status: :processing,
                      to_status: :completed,
                      duration_ms: 150
                    }}
  end

  test "task_failed/3 emits task_retried when attempts remain" do
    task =
      Repo.insert!(%Task{
        title: "Emit retry",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: %Task{id: task_id}, run: %Run{attempt: 1}}} =
             Processing.task_failed(task, %Result{duration: 240, message: "retry me"}, %{
               attempt: 1,
               max_attempts: 3
             })

    assert_receive {:task_retried,
                    %{
                      task_id: ^task_id,
                      from_status: :processing,
                      to_status: :queued,
                      duration_ms: 240,
                      attempt: 1
                    }}
  end

  test "task_failed/3 emits task_failed when the last attempt fails" do
    task =
      Repo.insert!(%Task{
        title: "Emit terminal failure",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :processing
      })

    assert {:ok, %{task: %Task{id: task_id}, run: %Run{attempt: 3}}} =
             Processing.task_failed(
               task,
               %Result{duration: 400, message: "failed permanently"},
               %{attempt: 3, max_attempts: 3}
             )

    assert_receive {:task_failed,
                    %{
                      task_id: ^task_id,
                      from_status: :processing,
                      to_status: :failed,
                      duration_ms: 400,
                      attempt: 3
                    }}
  end

  test "task_failed/3 does not emit retry or failure events when the transition is rejected" do
    task =
      Repo.insert!(%Task{
        title: "Rejected failure",
        type: :cleanup,
        priority: :low,
        payload: %{},
        max_attempts: 3,
        status: :queued
      })

    task_id = task.id

    assert {:error, :task, :not_retryable, %{}} =
             Processing.task_failed(task, %Result{duration: 200, message: "fail"}, %{
               attempt: 1,
               max_attempts: 3
             })

    refute_receive {:task_retried, %{task_id: ^task_id}}
    refute_receive {:task_failed, %{task_id: ^task_id}}
  end
end
