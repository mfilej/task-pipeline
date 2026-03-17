# Thoughts and notes

The exercise seemed to be simple on the surface, but I found something to consider at every step. This resulted in a lot of thinking, but not in a lot of code.

## State transitions and atomicity

To ensure atomicity when transitoining between states I opted for a guarded update_all pattern (check and write atomically). I can think of other options like SELECT FOR UPDATE, optimistic locking, … I think the approach I chose guarantees that the same Task can't be picked and transitioned by two workers at once, thus preventing corruption.

Initially, I started out using a FSM library, but in the end I felt the code was clearer this way with this limited number of possible transitions.

## One queue vs multiple queues

A single queue is simpler as we can't have starvation due to misconfiguration. But it doesn't offer the possibility to give higher-priority jobs the lower latency that they might require (all priorities compete for same workers). Separate queues can avoid having critical tasks delayed by low priority tasks. By specifications, the higher priority tasks are also shorter in execution time, so even with an equal number of workers per queue type, the higher priority queues would still have higher throughput.

## A note on enums

I went for native enums where I expect the values to be more or less stable, and I used integer-backed enums for the type, which feels like it could still evolve as the codebase grows.

## High-level code design and BDUF

I did not concern myself with additional code organization and how this might grow into a huge codebase. Partly because the exercie is quite abstract, but mainly because I find moving modules and functions to be relatively cheap (compared to non-functional langauges).

## A note on testing

TaskWorkerTest ended up acts as a high-level/integration test by fully exercising the retry/fail logic. Ideally I'd like this test to be more on a "unit" level, but here I made an exception, since I didn't have a better place for it yet.

## A note on generic naming

In a real codebase, both "task" and "run" would likely be too generic and I would try really hard to come up with better names. Here, due to the abstract nature of the exercise, they ended up being quite appropriate.

Similarly, we have a coupling between `task.priority` and queue name that would be a smell in a real codebase, but here it ends up working in our favour.

## UUID

In a real codebase I would've almost certainly used UUIDs. For this exercise, plain numeric IDs were still a nice help for their readability and predictability.

## Boundaries

I spent quite some time deciding what to delegate to Oban and what concerns belong into our business logic. At the end I decided that Oban should keep track of the attempt number, while the business logic will make sure to transition tasks to the correct state depending on that number. I think you could argue eiter way whether this is business logic or not, but I feel good about the final choice.

The decision to create a separate Run record for attempt tracking felt quite natural -- it feels appropriate to have 1 record for each attempt. I don't think it's necessarily wrong to have an array of attempts on the tasks table, but it seems unnecessary. Delegating this part to Oban I didn't feel so comfortable with -- I think this is one of those decisions that can end up being limiting in the long run, as the requirements grow, and the tool that you've piggy-backed your logic on doesn't let you extend it the way you want.

## Database indexes

I don't like adding indexes upfront and instead prefer to delay until I write the actual queries. From he requirements, I can guess at least guess that for the index endpoint: status, inserted_at, type, priority would be needed for filtering and sorting.

## What would change at a higher throughput?

I think the first thing we'd notice is queues backing up (depending on the number of workers). By observing the distribution of task priorities we could properly configure the number of workers (or even dynamically modify queues at runtime).

## Notable omissions

* fixtures/factories
* database indexes
* formatter plugins for more auto-formatting rules, like Eunomo for sorting imports
* API versioning
* A proper JSON serializer/presenter layer

## Note on AI usage

I had Tidewave generate mix tasks for testing, used it to add some missing test coverage, told it come up with a way to test the guarded update_all calls, and to do some light refactoring (I treated it more like an IDE with refactoring capabilities). I fully stand behind every line of code I'm submitting. I hope this was still in line with the spirit of the instructions.
