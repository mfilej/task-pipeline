defmodule TaskPipeline.Processing.HandlerTest do
  use TaskPipeline.DataCase, async: false

  alias TaskPipeline.Processing.Handler
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task

  test "run/1 with success" do
    task = %Task{priority: :critical}

    assert {:ok, %Result{duration: duration, message: message}} = Handler.run(task)
    assert duration in 1000..2000
    assert message == "Success in #{duration}ms"
  end

  test "run/1 with failure" do
    put_handler_failure_rate(1.0)

    task = %Task{priority: :critical}

    assert {:error, %Result{duration: duration, message: message}} = Handler.run(task)
    assert duration in 1000..2000
    assert message == "Failure in #{duration}ms"
  end
end
