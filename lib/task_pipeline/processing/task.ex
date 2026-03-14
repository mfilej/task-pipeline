defmodule TaskPipeline.Processing.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @types [import: 0, export: 1, report: 2, cleanup: 3]
  @priorities [:low, :normal, :high, :critical]
  @statuses [:queued, :processing, :completed, :failed]

  schema "tasks" do
    field :title, :string
    field :type, Ecto.Enum, values: @types
    field :priority, Ecto.Enum, values: @priorities
    field :payload, :map
    field :max_attempts, :integer, default: 3
    field :status, Ecto.Enum, values: @statuses

    timestamps(type: :utc_datetime)

    has_many :runs, TaskPipeline.Processing.Run
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :type, :priority, :payload, :max_attempts])
    |> validate_required([:title, :type, :priority, :payload])
    |> check_constraint(:max_attempts, name: :tasks_max_attempts_must_be_positive)
    |> put_change(:status, :queued)
  end

  def list_types, do: @types |> Keyword.keys()
  def list_priorities, do: @priorities
  def list_statuses, do: @statuses
end
