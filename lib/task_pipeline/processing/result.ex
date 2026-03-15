defmodule TaskPipeline.Processing.Result do
  @enforce_keys [:duration, :message]
  defstruct [:duration, :message]
end
