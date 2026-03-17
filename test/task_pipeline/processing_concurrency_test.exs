defmodule TaskPipeline.ProcessingConcurrencyTest do
  use TaskPipeline.DataCase, async: true

  alias TaskPipeline.Processing
  alias TaskPipeline.Processing.Task

  test "claim_task/1 allows only one concurrent claimant to win" do
    task =
      Repo.insert!(%Task{
        title: "Concurrent claim",
        type: :import,
        priority: :normal,
        payload: %{"id" => 790},
        max_attempts: 3,
        status: :queued
      })

    parent = self()

    claim = fn ->
      Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
      send(parent, {:ready, self()})

      receive do
        :go -> Processing.claim_task(task)
      end
    end

    first = Elixir.Task.async(claim)
    second = Elixir.Task.async(claim)
    first_pid = first.pid
    second_pid = second.pid

    assert_receive {:ready, ^first_pid}
    assert_receive {:ready, ^second_pid}

    send(first_pid, :go)
    send(second_pid, :go)

    results = [Elixir.Task.await(first), Elixir.Task.await(second)]

    assert Enum.count(results, &match?({:ok, %Task{status: :processing}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :not_claimable}, &1)) == 1
    assert Repo.get!(Task, task.id).status == :processing
  end
end
