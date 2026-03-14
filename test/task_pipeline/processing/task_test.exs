defmodule TaskPipeline.Processing.TaskTest do
  use TaskPipeline.DataCase, async: true

  import Ecto.Changeset

  alias TaskPipeline.Processing.Task

  test "changeset maps the positive max_attempts db constraint" do
    assert {:error, changeset} =
             %Task{}
             |> Task.changeset(%{
               title: "Process me",
               type: :import,
               priority: :high,
               payload: %{"id" => 123},
               max_attempts: 0
             })
             |> Repo.insert()

    assert "is invalid" in errors_on(changeset).max_attempts
  end

  test "changeset rejects unsupported priorities" do
    assert {:error, changeset} =
             %Task{}
             |> Task.changeset(%{
               title: "Bad priority",
               type: :import,
               priority: :unsupported,
               payload: %{"id" => 123}
             })
             |> Repo.insert()

    assert "is invalid" in errors_on(changeset).priority
  end

  test "changeset rejects unsupported types" do
    assert {:error, changeset} =
             %Task{}
             |> Task.changeset(%{
               title: "Bad type",
               type: :unsupported,
               priority: :high,
               payload: %{"id" => 123}
             })
             |> Repo.insert()

    assert "is invalid" in errors_on(changeset).type
  end

  test "insert rejects unsupported statuses" do
    assert_raise Ecto.ChangeError, ~r/does not match type/, fn ->
      %Task{}
      |> change(
        title: "Bad status",
        type: :import,
        priority: :high,
        payload: %{"id" => 123},
        max_attempts: 3,
        status: :unsupported
      )
      |> Repo.insert()
    end
  end
end
