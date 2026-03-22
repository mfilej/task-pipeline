defmodule TaskPipeline.Processing.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @types [import: 0, export: 1, report: 2, cleanup: 3]
  @priorities [critical: 0, high: 1, normal: 2, low: 3]
  @statuses [:queued, :processing, :completed, :failed]

  @derive {
    Flop.Schema,
    filterable: [:status, :type, :priority],
    sortable: [:priority, :inserted_at, :id],
    default_order: %{
      order_by: [:priority, :inserted_at, :id],
      order_directions: [:asc, :desc, :desc]
    },
    default_limit: 3,
    max_limit: 100,
    pagination_types: [:first],
    default_pagination_type: :first
  }

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
  def list_priorities, do: @priorities |> Keyword.keys()
  def list_statuses, do: @statuses
end
