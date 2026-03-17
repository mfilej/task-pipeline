# TaskPipeline

To start your Phoenix server:

* Install runtimes using [mise][]: `mise install`.
* Run `mix setup` to install deps and bootstrap the database.
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

## Oban web dashboard

Run it via docker with `mise run oban-dash`.

## Mix Tasks

Use these mix tasks to generate and enqueue Tasks:

* by creating a database record: `mix task_pipeline.enqueue_random`
* by hitting the create endpoint: `mix task_pipeline.create_via_api`

You can override the generated task fields:

```sh
PORT=4074 mix task_pipeline.create_via_api \
  --title "Smoke test" \
  --type import \
  --priority high \
  --payload '{"source":"mix_task"}' \
```

Allowed enum values:

* `--type`: `import`, `export`, `report`, `cleanup`
* `--priority`: `low`, `normal`, `high`, `critical`

[mise]: https://mise.jdx.dev/
