defmodule TaskPipelineWeb.TaskControllerTest do
  use TaskPipelineWeb.ConnCase

  alias TaskPipeline.Processing.Task
  alias TaskPipeline.Repo

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

  defp insert_task!(attrs \\ []) do
    defaults = %{
      title: "task",
      type: :import,
      priority: :normal,
      payload: %{},
      status: :queued,
      max_attempts: 3
    }

    Repo.insert!(struct(Task, Map.merge(defaults, Map.new(attrs))))
  end

  defp insert_run!(task, attrs) do
    alias TaskPipeline.Processing.Run

    Repo.insert!(%Run{
      task_id: task.id,
      attempt: Keyword.fetch!(attrs, :attempt),
      success: Keyword.fetch!(attrs, :success),
      message: Keyword.fetch!(attrs, :message)
    })
  end

  describe "index tasks" do
    test "returns empty list when no tasks exist", %{conn: conn} do
      conn = get(conn, ~p"/api/tasks")
      assert %{"data" => [], "meta" => _} = json_response(conn, 200)
    end

    test "returns all tasks", %{conn: conn} do
      insert_task!(title: "first")
      insert_task!(title: "second")

      conn = get(conn, ~p"/api/tasks")
      data = json_response(conn, 200)["data"]
      assert length(data) == 2
    end

    test "each task includes an href link to its detail", %{conn: conn} do
      task = insert_task!()
      conn = get(conn, ~p"/api/tasks")
      [item] = json_response(conn, 200)["data"]
      assert item["href"] == "/api/tasks/#{task.id}"
    end

    test "filters by status", %{conn: conn} do
      insert_task!(title: "queued", status: :queued)
      insert_task!(title: "completed", status: :completed)

      conn = get(conn, ~p"/api/tasks", status: "completed")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["title"] == "completed"
    end

    test "filters by type", %{conn: conn} do
      insert_task!(title: "import", type: :import)
      insert_task!(title: "export", type: :export)

      conn = get(conn, ~p"/api/tasks", type: "export")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["title"] == "export"
    end

    test "filters by priority", %{conn: conn} do
      insert_task!(title: "high", priority: :high)
      insert_task!(title: "low", priority: :low)

      conn = get(conn, ~p"/api/tasks", priority: "high")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["title"] == "high"
    end

    test "combines multiple filters", %{conn: conn} do
      insert_task!(title: "match", status: :queued, type: :import)
      insert_task!(title: "wrong status", status: :completed, type: :import)
      insert_task!(title: "wrong type", status: :queued, type: :export)

      conn = get(conn, ~p"/api/tasks", status: "queued", type: "import")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["title"] == "match"
    end

    test "sorts by priority desc then inserted_at desc", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -60)

      insert_task!(title: "low-newer", priority: :low, inserted_at: now, updated_at: now)

      insert_task!(
        title: "high-older",
        priority: :high,
        inserted_at: earlier,
        updated_at: earlier
      )

      insert_task!(title: "high-newer", priority: :high, inserted_at: now, updated_at: now)

      conn = get(conn, ~p"/api/tasks")
      titles = json_response(conn, 200)["data"] |> Enum.map(& &1["title"])
      assert titles == ["high-newer", "high-older", "low-newer"]
    end

    test "returns 422 for invalid filter values", %{conn: conn} do
      conn = get(conn, ~p"/api/tasks", status: "bogus")
      assert json_response(conn, 422)["errors"]
    end

    test "paginates with cursor-based pagination", %{conn: conn} do
      for i <- 1..5, do: insert_task!(title: "task #{i}")

      conn1 = get(conn, ~p"/api/tasks", first: "2")
      body1 = json_response(conn1, 200)
      assert length(body1["data"]) == 2
      assert body1["meta"]["has_next_page"] == true
      cursor = body1["meta"]["end_cursor"]

      conn2 = get(conn, ~p"/api/tasks", first: "2", after: cursor)
      body2 = json_response(conn2, 200)
      assert length(body2["data"]) == 2

      # No overlap between pages
      ids1 = Enum.map(body1["data"], & &1["id"])
      ids2 = Enum.map(body2["data"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
    end

    test "returns pagination meta", %{conn: conn} do
      conn = get(conn, ~p"/api/tasks")
      meta = json_response(conn, 200)["meta"]
      assert is_boolean(meta["has_next_page"])
      assert is_integer(meta["page_size"])
    end
  end

  describe "show task" do
    test "returns the task with its runs", %{conn: conn} do
      task = insert_task!(title: "detail me", status: :completed)
      insert_run!(task, attempt: 1, success: false, message: "boom")
      insert_run!(task, attempt: 2, success: true, message: "ok")

      conn = get(conn, ~p"/api/tasks/#{task.id}")
      body = json_response(conn, 200)["data"]

      assert body["id"] == task.id
      assert body["title"] == "detail me"
      assert body["status"] == "completed"
      assert body["href"] == "/api/tasks/#{task.id}"

      assert [run1, run2] = body["runs"]
      assert run1["attempt"] == 1
      assert run1["success"] == false
      assert run1["message"] == "boom"
      assert run2["attempt"] == 2
      assert run2["success"] == true
      assert run2["message"] == "ok"
    end

    test "returns runs ordered by attempt ascending", %{conn: conn} do
      task = insert_task!()
      insert_run!(task, attempt: 3, success: true, message: "third")
      insert_run!(task, attempt: 1, success: false, message: "first")
      insert_run!(task, attempt: 2, success: false, message: "second")

      conn = get(conn, ~p"/api/tasks/#{task.id}")
      attempts = json_response(conn, 200)["data"]["runs"] |> Enum.map(& &1["attempt"])
      assert attempts == [1, 2, 3]
    end

    test "returns 404 for a non-existent task", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/api/tasks/999999")
      end
    end
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
