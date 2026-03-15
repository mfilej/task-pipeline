defmodule TaskPipeline.Processing.RunTest do
  use TaskPipeline.DataCase, async: true

  alias TaskPipeline.Processing.Run
  alias TaskPipeline.Processing.Task

  test "changeset/4 valiates attributes" do
    task =
      Repo.insert!(%Task{
        title: "Process me",
        type: :import,
        priority: :high,
        payload: %{"id" => 123},
        max_attempts: 3,
        status: :queued
      })

    assert {:error, changeset} =
             %Run{}
             |> Run.changeset(task.id, false, %{attempt: 0, message: "boom"})
             |> Repo.insert()

    assert "is invalid" in errors_on(changeset).attempt
  end

  test "changeset/4 rejects duplicate attempts for the same task" do
    task =
      Repo.insert!(%Task{
        title: "Duplicate attempt task",
        type: :import,
        priority: :high,
        payload: %{"id" => 123},
        max_attempts: 3,
        status: :queued
      })

    Repo.insert!(Run.changeset(%Run{}, task.id, true, %{attempt: 1, message: "ok"}))

    assert {:error, changeset} =
             %Run{}
             |> Run.changeset(task.id, false, %{attempt: 1, message: "boom"})
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).attempt
  end
end
