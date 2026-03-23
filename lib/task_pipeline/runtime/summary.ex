defmodule TaskPipeline.Runtime.Summary do
  use GenServer

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Events

  @table __MODULE__
  @summary_key :summary
  @handled_events [:task_created, :task_claimed, :task_completed, :task_retried, :task_failed]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def summary do
    {:ok, read_summary()}
  end

  def rebuild do
    GenServer.call(__MODULE__, :rebuild)
  end

  @impl true
  def init(_opts) do
    ensure_table!()
    :ok = Events.subscribe()

    _ = refresh_summary()

    {:ok, :ok}
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    {:reply, {:ok, refresh_summary()}, state}
  end

  @impl true
  def handle_info({event_name, _payload}, state) when event_name in @handled_events do
    _ = refresh_summary()
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp refresh_summary do
    # NOTE: This is a naive approach where we refresh the summary on every event.
    # See NOTES.md for a discussion of better approaches.
    summary = Processing.tasks_summary()
    :ets.insert(@table, {@summary_key, summary})
    summary
  end

  defp read_summary do
    case :ets.whereis(@table) do
      :undefined ->
        Processing.tasks_summary()

      _table ->
        case :ets.lookup(@table, @summary_key) do
          [{@summary_key, summary}] -> summary
          [] -> Processing.tasks_summary()
        end
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
        :ok

      _table ->
        :ok
    end
  end
end
