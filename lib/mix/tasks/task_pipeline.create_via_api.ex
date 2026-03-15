defmodule Mix.Tasks.TaskPipeline.CreateViaApi do
  use Mix.Task

  alias TaskPipeline.Processing.Task

  @shortdoc "POSTs a task to the create API endpoint"

  @switches [
    title: :string,
    type: :string,
    priority: :string,
    payload: :string,
    max_attempts: :integer
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("loadpaths")
    Application.ensure_all_started(:req)

    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    payload = build_payload(opts)
    url = default_url()

    case Req.post(url, json: %{task: payload}) do
      {:ok, %Req.Response{status: status, body: body}} ->
        Mix.shell().info("POST #{url}")
        Mix.shell().info("Status: #{status}")
        Mix.shell().info(Jason.encode_to_iodata!(body, pretty: true) |> IO.iodata_to_binary())

      {:error, exception} ->
        Mix.raise("Request failed: #{Exception.message(exception)}")
    end
  end

  defp build_payload(opts) do
    %{
      title: Keyword.get(opts, :title, "API task #{System.unique_integer([:positive])}"),
      type: Keyword.get(opts, :type, "import") |> parse_enum!(:type, Task.list_types()),
      priority:
        Keyword.get(opts, :priority, "normal") |> parse_enum!(:priority, Task.list_priorities()),
      payload:
        parse_payload(
          Keyword.get(opts, :payload, ~s({"source":"mix task_pipeline.create_via_api"}))
        ),
      max_attempts: Keyword.get(opts, :max_attempts, 3)
    }
  end

  defp parse_enum!(value, field, allowed_values) when is_binary(value) do
    atom_value = String.to_existing_atom(value)

    if atom_value in allowed_values do
      value
    else
      Mix.raise(
        "Invalid #{field}: #{inspect(value)}. Allowed values: #{Enum.join(allowed_values, ", ")}"
      )
    end
  rescue
    ArgumentError ->
      Mix.raise(
        "Invalid #{field}: #{inspect(value)}. Allowed values: #{Enum.join(allowed_values, ", ")}"
      )
  end

  defp parse_payload(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} when is_map(decoded) -> decoded
      {:ok, _decoded} -> Mix.raise("--payload must decode to a JSON object")
      {:error, error} -> Mix.raise("Invalid JSON payload: #{Exception.message(error)}")
    end
  end

  defp default_url do
    endpoint = Application.fetch_env!(:task_pipeline, TaskPipelineWeb.Endpoint)
    port = System.get_env("PORT", "4000")
    host = endpoint[:url][:host] || "localhost"
    scheme = endpoint[:url][:scheme] || "http"

    "#{scheme}://#{host}:#{port}/api/tasks"
  end
end
