defmodule TaskPipeline.Runtime.SummaryTest do
  use TaskPipeline.DataCase, async: false

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Runtime.Summary
  alias TaskPipeline.Processing.Task

  setup do
    start_supervised!(Summary)
    _ = :sys.get_state(Summary)
    :ok
  end

  test "summary/0 rebuilds from Postgres and normalizes missing statuses" do
    assert {:ok, %{queued: 0, processing: 0, completed: 0, failed: 0}} = Summary.summary()

    Repo.insert!(%Task{
      title: "queued task",
      type: :import,
      priority: :normal,
      payload: %{},
      status: :queued
    })

    Repo.insert!(%Task{
      title: "completed task",
      type: :report,
      priority: :high,
      payload: %{},
      status: :completed
    })

    assert {:ok, %{queued: 1, processing: 0, completed: 1, failed: 0}} = Summary.rebuild()
    assert {:ok, %{queued: 1, processing: 0, completed: 1, failed: 0}} = Summary.summary()
  end

  test "summary/0 tracks lifecycle events incrementally" do
    attrs = %{
      title: "cached task",
      type: :import,
      priority: :high,
      payload: %{"source" => "summary-cache"}
    }

    assert {:ok, %{task: task}} = Processing.create_task(attrs)
    _ = :sys.get_state(Summary)
    assert {:ok, %{queued: 1, processing: 0, completed: 0, failed: 0}} = Summary.summary()

    assert {:ok, %{task: task}} = Processing.claim_task(task)
    _ = :sys.get_state(Summary)
    assert {:ok, %{queued: 0, processing: 1, completed: 0, failed: 0}} = Summary.summary()

    assert {:ok, %{task: _task, run: _run}} =
             Processing.task_completed(task, %Result{duration: 125, message: "done"}, %{
               attempt: 1
             })

    _ = :sys.get_state(Summary)
    assert {:ok, %{queued: 0, processing: 0, completed: 1, failed: 0}} = Summary.summary()
  end

  test "rebuild/0 reconciles direct repo writes outside evented APIs" do
    assert {:ok, %{queued: 0, processing: 0, completed: 0, failed: 0}} = Summary.summary()

    Repo.insert!(%Task{
      title: "repo task",
      type: :cleanup,
      priority: :low,
      payload: %{},
      status: :failed
    })

    assert {:ok, %{queued: 0, processing: 0, completed: 0, failed: 0}} = Summary.summary()
    assert {:ok, %{queued: 0, processing: 0, completed: 0, failed: 1}} = Summary.rebuild()
  end

  test "restarts by rebuilding summary state from Postgres" do
    Repo.insert!(%Task{
      title: "restarted queued task",
      type: :import,
      priority: :normal,
      payload: %{},
      status: :queued
    })

    Repo.insert!(%Task{
      title: "restarted failed task",
      type: :cleanup,
      priority: :low,
      payload: %{},
      status: :failed
    })

    assert {:ok, %{queued: 0, processing: 0, completed: 0, failed: 0}} = Summary.summary()

    restarted_pid = restart_process!(Summary)

    assert is_pid(restarted_pid)
    assert {:ok, %{queued: 1, processing: 0, completed: 0, failed: 1}} = Summary.summary()
  end

  test "duplicate transition events do not double count" do
    attrs = %{
      title: "duplicate event task",
      type: :export,
      priority: :normal,
      payload: %{"source" => "dup"}
    }

    assert {:ok, %{task: task}} = Processing.create_task(attrs)
    _ = :sys.get_state(Summary)
    assert {:ok, %{queued: 1, processing: 0, completed: 0, failed: 0}} = Summary.summary()

    send(Summary, {:task_created, %{task_id: task.id, from_status: nil, to_status: :queued}})
    _ = :sys.get_state(Summary)

    assert {:ok, %{queued: 1, processing: 0, completed: 0, failed: 0}} = Summary.summary()
  end

  defp restart_process!(name) do
    pid = Process.whereis(name)
    ref = Process.monitor(pid)

    Process.exit(pid, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    restarted_pid = wait_for_restart(name, pid)
    _ = :sys.get_state(name)
    restarted_pid
  end

  defp wait_for_restart(name, old_pid, attempts \\ 10)

  defp wait_for_restart(_name, _old_pid, 0) do
    flunk("expected supervised process to restart")
  end

  defp wait_for_restart(name, old_pid, attempts) do
    case Process.whereis(name) do
      nil ->
        schedule_restart_check()
        wait_for_restart(name, old_pid, attempts - 1)

      ^old_pid ->
        schedule_restart_check()
        wait_for_restart(name, old_pid, attempts - 1)

      restarted_pid ->
        restarted_pid
    end
  end

  defp schedule_restart_check do
    marker = make_ref()
    Process.send_after(self(), {:restart_check, marker}, 10)
    assert_receive {:restart_check, ^marker}
  end
end
