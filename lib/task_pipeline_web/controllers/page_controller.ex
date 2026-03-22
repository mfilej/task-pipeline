defmodule TaskPipelineWeb.PageController do
  use TaskPipelineWeb, :controller

  def index(conn, _params) do
    send_resp(conn, 200, "")
  end
end
