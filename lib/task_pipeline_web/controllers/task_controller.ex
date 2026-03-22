defmodule TaskPipelineWeb.TaskController do
  use TaskPipelineWeb, :controller

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Task

  action_fallback TaskPipelineWeb.FallbackController

  def index(conn, params) do
    # NOTE: This allows for far more than just the required filters and default
    # sorting. However, the exisitng database indexes only support the default
    # sort order + filtering on priority, status, and type.
    pagination_params = FlopRest.normalize(params, for: Task)

    with {:ok, {tasks, meta}} <- Processing.list_tasks(pagination_params) do
      render(conn, :index, tasks: tasks, meta: meta)
    end
  end

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
