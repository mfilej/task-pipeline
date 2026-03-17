defmodule TaskPipelineWeb.TaskJSON do
  alias TaskPipeline.Processing.Task

  def show(%{task: task}) do
    %{data: data(task)}
  end

  defp data(%Task{} = task) do
    Map.take(task, [:id, :title, :type, :priority, :payload, :status])
  end
end
