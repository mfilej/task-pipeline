defmodule TaskPipeline.Runtime.Metrics do
  use GenServer

  alias TaskPipeline.Processing.Events

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @impl true
  def init(_opts) do
    :ok = Events.subscribe()

    # NOTE: counters start from zero on restart
    {:ok, zero_state()}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, snapshot_from(state)}, state}
  end

  @impl true
  def handle_info({:task_completed, payload}, state) do
    {:noreply, update_state(state, :completed_count, payload)}
  end

  def handle_info({:task_retried, payload}, state) do
    {:noreply, update_state(state, :retried_count, payload)}
  end

  def handle_info({:task_failed, payload}, state) do
    {:noreply, update_state(state, :failed_count, payload)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp zero_state do
    %{
      completed_count: 0,
      failed_count: 0,
      retried_count: 0,
      total_processing_duration_ms: 0,
      duration_sample_count: 0
    }
  end

  defp update_state(state, counter, %{duration_ms: duration_ms})
       when is_integer(duration_ms) and duration_ms >= 0 do
    state
    |> increment(counter)
    |> increment(:duration_sample_count)
    |> add_duration(duration_ms)
  end

  defp update_state(state, counter, _payload) do
    increment(state, counter)
  end

  defp increment(state, key) do
    Map.update!(state, key, &(&1 + 1))
  end

  defp add_duration(state, duration_ms) do
    Map.update!(state, :total_processing_duration_ms, &(&1 + duration_ms))
  end

  defp snapshot_from(state) do
    %{
      completed_count: state.completed_count,
      failed_count: state.failed_count,
      retried_count: state.retried_count,
      average_processing_duration_ms: average_duration_ms(state),
      terminal_failure_rate: terminal_failure_rate(state)
    }
  end

  defp average_duration_ms(%{duration_sample_count: 0}) do
    0
  end

  defp average_duration_ms(state) do
    round(state.total_processing_duration_ms / state.duration_sample_count)
  end

  defp terminal_failure_rate(%{failed_count: 0}) do
    0.0
  end

  defp terminal_failure_rate(state) do
    terminal_outcome_count = state.completed_count + state.failed_count
    Float.round(state.failed_count / terminal_outcome_count, 4)
  end
end
