defmodule TaskPipeline.Runtime.MetricsTest do
  use TaskPipeline.DataCase, async: false

  alias TaskPipeline.Processing
  alias TaskPipeline.Runtime.Metrics
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task

  setup do
    start_supervised!(Metrics)
    _ = :sys.get_state(Metrics)
    :ok
  end

  test "snapshot/0 starts with zeroed process-lifetime metrics" do
    assert {:ok, metrics} = Metrics.snapshot()
    assert metrics.completed_count == 0
    assert metrics.failed_count == 0
    assert metrics.retried_count == 0
    assert metrics.average_processing_duration_ms == 0
    assert_in_delta metrics.terminal_failure_rate, 0.0, 0.0001
  end

  test "snapshot/0 tracks completions, retries, failures, and rolling averages" do
    retried_task = insert_processing_task!("retry me")
    completed_task = insert_processing_task!("complete me")
    failed_task = insert_processing_task!("fail me")

    assert {:ok, %{task: %Task{status: :queued}}} =
             Processing.task_failed(retried_task, %Result{duration: 240, message: "retry"}, %{
               attempt: 1,
               max_attempts: 3
             })

    assert {:ok, %{task: %Task{status: :completed}}} =
             Processing.task_completed(completed_task, %Result{duration: 120, message: "done"}, %{
               attempt: 1
             })

    assert {:ok, %{task: %Task{status: :failed}}} =
             Processing.task_failed(failed_task, %Result{duration: 480, message: "boom"}, %{
               attempt: 3,
               max_attempts: 3
             })

    _ = :sys.get_state(Metrics)

    assert {:ok, metrics} = Metrics.snapshot()
    assert metrics.completed_count == 1
    assert metrics.failed_count == 1
    assert metrics.retried_count == 1
    assert metrics.average_processing_duration_ms == 280
    assert_in_delta metrics.terminal_failure_rate, 0.5, 0.0001
  end

  test "restarts with zeroed state and resumes counting new events" do
    completed_task = insert_processing_task!("before restart")

    assert {:ok, %{task: %Task{status: :completed}}} =
             Processing.task_completed(completed_task, %Result{duration: 120, message: "done"}, %{
               attempt: 1
             })

    _ = :sys.get_state(Metrics)

    assert {:ok, metrics} = Metrics.snapshot()
    assert metrics.completed_count == 1

    restarted_pid = restart_process!(Metrics)
    assert is_pid(restarted_pid)

    assert {:ok, metrics} = Metrics.snapshot()
    assert metrics.completed_count == 0
    assert metrics.failed_count == 0
    assert metrics.retried_count == 0
    assert metrics.average_processing_duration_ms == 0
    assert_in_delta metrics.terminal_failure_rate, 0.0, 0.0001

    failed_task = insert_processing_task!("after restart")

    assert {:ok, %{task: %Task{status: :failed}}} =
             Processing.task_failed(failed_task, %Result{duration: 300, message: "boom"}, %{
               attempt: 3,
               max_attempts: 3
             })

    _ = :sys.get_state(Metrics)

    assert {:ok, metrics} = Metrics.snapshot()
    assert metrics.completed_count == 0
    assert metrics.failed_count == 1
    assert metrics.retried_count == 0
    assert metrics.average_processing_duration_ms == 300
    assert_in_delta metrics.terminal_failure_rate, 1.0, 0.0001
  end

  defp insert_processing_task!(title) do
    Repo.insert!(%Task{
      title: title,
      type: :cleanup,
      priority: :normal,
      payload: %{},
      max_attempts: 3,
      status: :processing
    })
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
