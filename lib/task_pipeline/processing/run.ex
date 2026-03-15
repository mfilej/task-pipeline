defmodule TaskPipeline.Processing.Run do
  @moduledoc """
  Records a completed task run (successful or otherwise).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "runs" do
    field :attempt, :integer
    field :success, :boolean
    field :message, :string

    timestamps(updated_at: false, type: :utc_datetime)

    belongs_to :task, TaskPipeline.Processing.Task
  end

  def changeset(run, task_id, success, %{message: message, attempt: attempt}) do
    run
    |> cast(%{message: message, attempt: attempt}, [:attempt, :message])
    |> put_change(:task_id, task_id)
    |> put_change(:success, success)
    |> check_constraint(:attempt, name: :runs_attempt_must_be_positive)
    |> foreign_key_constraint(:task_id)
    |> unique_constraint(:attempt, name: :runs_task_id_attempt_index)
  end
end
