defmodule TaskPipeline.Processing.Events do
  alias Phoenix.PubSub
  alias TaskPipeline.PubSub, as: TaskPipelinePubSub
  alias TaskPipeline.Processing.Result
  alias TaskPipeline.Processing.Task

  @topic "processing:lifecycle"

  def topic, do: @topic

  def subscribe do
    PubSub.subscribe(TaskPipelinePubSub, @topic)
  end

  def task_created(%{task: %Task{id: task_id}}) do
    broadcast({:task_created, %{task_id: task_id, from_status: nil, to_status: :queued}})
  end

  def task_claimed(%{task: %Task{id: task_id}}) do
    broadcast({:task_claimed, %{task_id: task_id, from_status: :queued, to_status: :processing}})
  end

  def task_completed(%{task: %Task{id: task_id}, result: %Result{duration: duration_ms}}) do
    broadcast(
      {:task_completed,
       %{
         task_id: task_id,
         from_status: :processing,
         to_status: :completed,
         duration_ms: duration_ms
       }}
    )
  end

  def task_retried(%{
        task: %Task{id: task_id},
        result: %Result{duration: duration_ms},
        meta: %{attempt: attempt}
      }) do
    broadcast(
      {:task_retried,
       %{
         task_id: task_id,
         from_status: :processing,
         to_status: :queued,
         duration_ms: duration_ms,
         attempt: attempt
       }}
    )
  end

  def task_failed(%{
        task: %Task{id: task_id},
        result: %Result{duration: duration_ms},
        meta: %{attempt: attempt}
      }) do
    broadcast(
      {:task_failed,
       %{
         task_id: task_id,
         from_status: :processing,
         to_status: :failed,
         duration_ms: duration_ms,
         attempt: attempt
       }}
    )
  end

  defp broadcast(message) do
    PubSub.broadcast(TaskPipelinePubSub, @topic, message)
  end
end
