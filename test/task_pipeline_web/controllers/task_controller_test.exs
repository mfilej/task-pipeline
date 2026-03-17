defmodule TaskPipelineWeb.TaskControllerTest do
  use TaskPipelineWeb.ConnCase

  @create_attrs %{
    priority: "high",
    type: "import",
    title: "test task",
    payload: %{"source" => "controller test"}
  }
  @invalid_attrs %{
    priority: nil,
    type: nil,
    max_attempts: nil,
    title: nil,
    payload: nil
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create task" do
    test "renders task when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/tasks", task: @create_attrs)
      assert %{"title" => "test task", "status" => "queued"} = json_response(conn, 201)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/tasks", task: @invalid_attrs)
      assert %{"title" => ["can't be blank"]} = json_response(conn, 422)["errors"]
    end
  end
end
