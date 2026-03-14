defmodule TaskPipeline.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :type, :integer, null: false
      add :priority, :task_priority, null: false
      add :payload, :map, null: false
      add :max_attempts, :integer, default: 3, null: false
      add :status, :task_status, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:tasks, :tasks_max_attempts_must_be_positive, check: "max_attempts > 0")
  end
end
