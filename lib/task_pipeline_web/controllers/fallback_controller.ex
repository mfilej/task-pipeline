defmodule TaskPipelineWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use TaskPipelineWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: TaskPipelineWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, %Flop.Meta{} = meta}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: TaskPipelineWeb.FlopErrorJSON)
    |> render(:error, meta: meta)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: TaskPipelineWeb.ErrorJSON)
    |> render(:"404")
  end
end
