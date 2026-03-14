defmodule TaskPipeline.Repo.Migrations.CreateTaskPriorityEnum do
  use Ecto.Migration

  def up do
    execute("""
      CREATE TYPE task_priority AS ENUM ('low', 'normal', 'high', 'critical')
    """)
  end

  def down do
    execute("DROP TYPE task_priority")
  end
end
