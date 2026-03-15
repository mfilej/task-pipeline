defmodule TaskPipeline.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :attempt, :integer, null: false
      add :success, :boolean, default: false, null: false
      add :message, :string, null: false
      add :task_id, references(:tasks, on_delete: :nothing), null: false

      timestamps(updated_at: false)
    end

    create constraint(:runs, :runs_attempt_must_be_positive, check: "attempt > 0")
    create unique_index(:runs, [:task_id, :attempt])
  end
end
