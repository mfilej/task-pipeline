# Thoughts and notes

The exercise seemed to be simple on the surface, but I found something to consider at every step. This resulted in a lot of thinking, but not in a lot of code.

## State transitions and atomicity

To ensure atomicity when transitioning between states I opted for a guarded `update_all` pattern (check and write atomically). I can think of other options like `SELECT FOR UPDATE` or optimistic locking, but I think the approach I chose guarantees that the same task cannot be picked and transitioned by two workers at once, thus preventing corruption.

Initially, I started out using a FSM library, but in the end I felt the code was clearer this way with this limited number of possible transitions.

## One queue vs multiple queues

A single queue is simpler as we can't have starvation due to misconfiguration. But it doesn't offer the possibility to give higher-priority jobs the lower latency that they might require (all priorities compete for same workers). Separate queues can avoid having critical tasks delayed by low priority tasks. By specifications, the higher priority tasks are also shorter in execution time, so even with an equal number of workers per queue type, the higher priority queues would still have higher throughput.

## Enums and pagination

I went for enums where I expect the values to be more or less stable, and I ended up using integer-backed enums once sorting and pagination constraints became clearer. `priority` in particular now sorts the way the API needs, and using ordered enums also makes the integration with Flop smoother (and the order explicit to the reader).

Cursor-based pagination requires a deterministic order, so the list endpoint sorts by priority and timestamps with `id` as the final tiebreaker. The endpoint currently exposes only forward pagination.

## OTP design

### Supervisor & subtree

The root application supervisor now keeps only infrastructure-level concerns: telemetry, repo, clustering, PubSub, Oban, and the endpoint. Application-owned OTP concerns now hang off a dedicated `TaskPipeline.Runtime.Supervisor` subtree instead of being attached directly to the root.

I kept that subtree on `:one_for_one` because the planned runtime children (summary cache, metrics, monitoring, caching) are independent consumers of the same events, so one crashing should not force the others to restart. I also start PubSub and the runtime subtree before Oban and the endpoint so subscribers can be in place before publishers begin emitting lifecycle events.

Task lifecycle changes publish PubSub events after successful writes, which keeps the write path focused on correctness and lets projections and metrics react without being tightly coupled to the core processing logic.

### Crash recovery and read models

The summary endpoint reads from ETS for the fast path, but falls back to a repo query so Postgres remains the source of truth if the cache is unavailable or stale. `Summary` is treated as a rebuildable projection, not as a source of truth. On startup or restart it subscribes to lifecycle events and rebuilds from `tasks`, so a crash only loses in-memory performance state.

`Metrics` only holds its state as long as the process is alive. On restart it resets to zero and begins counting new lifecycle events again. I chose that trade-off to keep the implementation small and explicit for the exercise. If exact historical metrics mattered, the next step would be rebuilding from `runs` or persisting rollups instead of pretending GenServer state is durable history.

There was an interesting choice to make here between listening to our PubSub events or relying on `:telemetry` data emitted by Oban. Given the wording "Track task throughput" I went for the former.

### Skipped patterns

* A `DynamicSupervisor` would be redundant for task execution in this codebase, because Oban already owns that responsibility.
* `Registry` or other discovery patterns might make sense if the runtime subtree grows and/or the processes need to be able to communicate (rather than using PubSub).

## Scaling analysis

At 10k tasks/min, the database would likely become the main bottleneck before the application layer, especially in the following areas:
* task inserts and Oban job inserts
* frequent state changes
* continued growth of the runs table

The current queue split by priority is a good starting point, but under sustained load I would expect to rebalance worker counts per queue and potentially shard further based on workload shape if one class of jobs begins to dominate throughput or latency.

I would consider moving list and summary-style reads to a read replica once read volume becomes significant. That introduces replica lag, so those endpoints would become eventually consistent. `create` and `detail` calls should continue to rely on the primary.

The current summary projection is acceptable only as a simple exercise implementation; in reality I would replace the current rebuild-on-event approach described below.

Pruning and possibly archiving or partitioning would become necessary for runs and Oban tables (and potentially for tasks as well depending on how long completed work needs to remain queryable).

### Summary projection and cache correctness

The scan cost for the aggregate query to gather counts will grow significantly once we approach 10^5, 10^6, … rows. Depending on how often the endpoint is hit, we might be compelled to implement some form of caching. A simple task_counts table would be a natural fit here, since we already have the Ecto.Multi structure when inserting and changing statuses. This also avoids any issues with multi-node deployments (unless the summary endpoint is hit *really* often, in which case an in-memory cache will be more suitable).

Instead of the cache running the aggregate query, a much cheaper approach is to have a count for each state and increment/decrement depending on the `from_status` and `to_status` on the events. This approach requires some additional work to ensure correctness (a monotonic version counter on tasks or similar, to guard against out-of-order events and similar situations that could corrupt counters).

The cache invalidation strategy in our case is event driven: we recompute the summary on every state transition event. With any significant task throughput this would quickly become a bottleneck. A straightforward solution is to only refresh the cache after a given time interval has passed (if requirements allow for some staleness). For crash recovery (and startup) we need the full rebuild with either approach, with the additional question of timing because we do not want task transitions to start before the cache has a chance to begin listening.

## What I would build in a week vs. what I built in a few hours

In the available time I focused on a solid baseline: the core task API, transactional task creation and enqueueing, guarded lifecycle transitions, attempt tracking, summary and metrics endpoints, and enough test coverage to exercise the main happy paths, failures, and concurrency-sensitive transitions.

With a full week, I would push the design further in the areas that matter most at scale: smarter summary caching, better observability (to be able to tune the queues), explain plans and additional indexes as needed, more realistic load and concurrency testing. With fewer scaling requirements I could instead also focus on a cleaner presentation layer with API versioning, and test fixtures/factories.

## A note on testing

`TaskWorkerTest` ended up acting as a high-level integration test by fully exercising the retry/fail logic. Ideally I'd like this test to be more on a unit level, but here I made an exception since I did not have a better place for it yet.

## A note on generic naming

In a real codebase, both "task" and "run" would likely be too generic and I would try really hard to come up with better names. Here, due to the abstract nature of the exercise, they ended up being quite appropriate.

Similarly, we have a coupling between `task.priority` and queue name that would be a smell in a real codebase, but here it ends up working in our favour.

## UUID

In a real codebase I would've almost certainly used UUIDs. For this exercise, plain numeric IDs were still a nice help for their readability and predictability.

## Boundaries and dependency directions

I spent quite some time deciding what to delegate to Oban and what concerns belong into our business logic. At the end I decided that Oban should keep track of the attempt number, while the business logic will make sure to transition tasks to the correct state depending on that number. I think you could argue either way whether this is business logic or not, but I feel good about the final choice.

The decision to create a separate Run record for attempt tracking felt quite natural; it feels appropriate to have one record for each attempt. I do not think it is necessarily wrong to have an array of attempts on the tasks table, but it seems unnecessary. Delegating this part to Oban I did not feel so comfortable with. I think this is one of those decisions that can end up being limiting in the long run, as the requirements grow and the tool that you have piggy-backed your logic on does not let you extend it the way you want.

A conscious choice was to make `Runtime.*` call out to `Processing`. `Processing` does not depend on `Runtime.*`.

## Shortcuts, notable omissions, and things I wouldn't do in a real project

* Fixtures/factories
* Editing existing migrations 
* Formatter plugins for more auto-formatting rules, like Eunomo for sorting imports
* API versioning
* A proper JSON serializer/presenter layer, and possibly better file structure in that department.
* Metrics is only partially complete; hopefully enough to illustrate the approach.
* Explicit happy-path schema and changeset tests for `Task` and `Run`.
* I did not concern myself with additional code organization and how this might grow into a huge codebase. Partly because the exercise is quite abstract, but mainly because I find moving modules and functions to be relatively cheap (compared to non-functional languages).

## Note on AI usage

I had Tidewave generate mix tasks for testing, used it to add some missing test coverage, told it to come up with a way to test the guarded update_all calls, and to do some light refactoring (I treated it more like an IDE with refactoring capabilities). I fully stand behind every line of code I'm submitting. I hope this was still in line with the spirit of the instructions.
UPDATE: The second part of the assignment also leaned on AI to improve test coverage in some areas (you will notice some of them are quite vibe-y).
