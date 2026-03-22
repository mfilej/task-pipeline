defmodule TaskPipeline.Repo.Migrations.AddTaskListIndexes do
  use Ecto.Migration

  def change do
    # Supports the default list sort: ORDER BY priority ASC, inserted_at DESC, id DESC
    # and cursor pagination on (priority, inserted_at, id)
    create index(:tasks, ["priority ASC", "inserted_at DESC", "id DESC"])

    # Supports equality filters on individual columns
    create index(:tasks, [:status])
    create index(:tasks, [:type])
  end
end
