defmodule TaskPipeline.Seeds do
  import Ecto.Query
  alias TaskPipeline.Repo
  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Task

  def create_tasks do
    types = Task.list_types()
    statuses = Task.list_statuses()
    priorities = Task.list_priorities()

    tasks =
      for i <- 1..100 do
        %{
          title: "Task #{i}",
          type: types |> Enum.random(),
          priority: priorities |> Enum.random(),
          status: statuses |> Enum.random(),
          max_attempts: 3,
          payload: %{},
          inserted_at: now(),
          updated_at: now()
        }
      end

    Repo.insert_all(Task, tasks)
  end

  def create_runs do
    runs =
      Task
      |> where([t], t.status in [:completed, :failed])
      |> Repo.all()
      |> Enum.map(fn task ->
        Map.merge(
          status_based_attrs(task.status),
          %{
            task_id: task.id,
            attempt: 1,
            inserted_at: now()
          }
        )
      end)

    Repo.insert_all(Run, runs)
  end

  defp status_based_attrs(:completed) do
    %{success: true, message: "Great success!"}
  end

  defp status_based_attrs(:failed) do
    %{success: false, message: "Epic fail!"}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
