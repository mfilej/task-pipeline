defmodule TaskPipeline.Processing.Handler do
  @moduledoc """
  Simulates doing work on a given task.
  In reality, we'd probably have separate handlers depending on the task type.
  """

  alias TaskPipeline.Processing.Result

  @processing_enabled Application.compile_env!(:task_pipeline, [__MODULE__, :processing_enabled])

  def run(task) do
    duration = processing_time(task.priority)

    maybe_sleep(duration)

    if success?() do
      {:ok, %Result{duration: duration, message: "Success in #{duration}ms"}}
    else
      {:error, %Result{duration: duration, message: "Failure in #{duration}ms"}}
    end
  end

  defp processing_time(:critical), do: Enum.random(1000..2000)
  defp processing_time(:high), do: Enum.random(2000..4000)
  defp processing_time(:normal), do: Enum.random(4000..6000)
  defp processing_time(:low), do: Enum.random(6000..8000)

  defp success? do
    failure_rate = Application.fetch_env!(:task_pipeline, :handler_failure_rate)

    :rand.uniform() > failure_rate
  end

  defp maybe_sleep(duration) do
    if @processing_enabled do
      Process.sleep(duration)
    end
  end
end
