defmodule TaskPipeline.Repo.Migrations.CreateTaskStatusEnum do
  use Ecto.Migration

  def up do
    execute("""
      CREATE TYPE task_status AS ENUM ('queued', 'processing', 'completed', 'failed')
    """)
  end

  def down do
    execute("DROP TYPE task_status")
  end
end
