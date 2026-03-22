defmodule TaskPipelineWeb.FlopErrorJSON do
  # TODO: surface per-field Flop validation errors for production use
  def error(%{meta: %Flop.Meta{}}) do
    %{errors: %{detail: "invalid query parameters"}}
  end
end
