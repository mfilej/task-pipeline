defmodule TaskPipelineWeb.TaskJSON do
  alias TaskPipeline.Processing.Task

  use TaskPipelineWeb, :verified_routes

  def index(%{tasks: tasks, meta: meta}) do
    %{
      data: Enum.map(tasks, &task_data/1),
      meta: pagination_meta(meta)
    }
  end

  def show(%{task: task}) do
    %{data: task_data(task)}
  end

  defp task_data(%Task{} = task) do
    task
    |> Map.take([
      :id,
      :title,
      :type,
      :priority,
      :payload,
      :status,
      :max_attempts,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:href, ~p"/api/tasks/#{task}")
  end

  defp pagination_meta(%Flop.Meta{} = meta) do
    %{
      has_next_page: meta.has_next_page?,
      end_cursor: meta.end_cursor,
      page_size: meta.page_size
    }
  end
end
