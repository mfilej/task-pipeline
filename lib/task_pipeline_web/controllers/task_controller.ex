defmodule TaskPipelineWeb.TaskController do
  use TaskPipelineWeb, :controller

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Task

  action_fallback TaskPipelineWeb.FallbackController

  def create(conn, %{"task" => task_params}) do
    case Processing.create_task(task_params) do
      {:ok, %{task: %Task{} = task}} ->
        conn
        |> put_status(:created)
        |> render(:show, task: task)

      {:error, :task, changeset, _changes_so_far} ->
        {:error, changeset}
    end
  end
end
