# async_parallel

`moonbit-community/quickcheck_statemachine/async_parallel` is the async
parallel testing entry point for `quickcheck_statemachine`. It keeps the model,
generation, reference binding, and coverage interfaces from the synchronous
state machine API. Callbacks that interact with the system under test use async
forms. Use it to test stateful programs whose operations may interleave at
`@async` scheduling points.

This package is useful for testing:

- shared mutable systems such as async queues, connection pools, caches,
  database clients, and file system wrappers;
- races that only appear when two operations run concurrently;
- existing synchronous `StateMachine` specifications that need to move to an
  async runner;
- scenarios that need to record the real invocation/response history and check
  whether that history is linearizable.

The package's `moon.pkg` declares `supported_targets = "native"`. Tests that
use these APIs should also run under the native target.

## Quick Example

The following example manually builds a `ParallelCommands` value. It has no
prefix. The left branch increments a counter once, and the right branch reads
the counter. `run_command` calls `@async.pause()`, so the two branches may
interleave during execution. The runner records the real history and checks
whether that history has a valid sequential explanation.

```mbt check
///|
enum DemoCommand {
  DemoIncr
  DemoGet
} derive(Eq, Debug)

///|
enum DemoResponse {
  DemoUnit
  DemoValue(Int32)
} derive(Eq, Debug)

///|
struct DemoSystem {
  mut value : Int32
}

///|
fn demo_expected(model : Int32, command : DemoCommand) -> DemoResponse {
  match command {
    DemoIncr => DemoUnit
    DemoGet => DemoValue(model)
  }
}

///|
fn demo_transition(
  model : Int32,
  command : DemoCommand,
  response : DemoResponse,
) -> Int32 {
  ignore(response)
  match command {
    DemoIncr => model + 1
    DemoGet => model
  }
}

///|
fn demo_command(
  command : DemoCommand,
  response : DemoResponse,
) -> @qsm.Command[DemoCommand, DemoResponse] {
  @qsm.Command::{ command, response, vars: [], }
}

///|
fn demo_spec() -> @async_parallel.AsyncStateMachine[
  Int32,
  Int32,
  DemoCommand,
  DemoCommand,
  DemoResponse,
  DemoResponse,
  Unit,
  DemoSystem,
] {
  @async_parallel.AsyncStateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => { value: 0, },
    generator=(_, _, _) => None,
    mock=(model, command, gen_sym) => (demo_expected(model, command), gen_sym),
    transition_symbolic=demo_transition,
    transition_concrete=demo_transition,
    reify_command=(command, _) => Ok(command),
    run_command=(command, system) => {
      match command {
        DemoIncr => {
          @async.pause()
          system.value += 1
          DemoUnit
        }
        DemoGet => {
          @async.pause()
          DemoValue(system.value)
        }
      }
    },
    bind_response=(_, _, environment) => Ok(environment),
    postcondition=(model, command, response) => {
      @qsm.Logic::predicate(
        name="response matches the model",
        value=response == demo_expected(model, command),
      )
    },
    command_name=command => {
      match command {
        DemoIncr => "incr"
        DemoGet => "get"
      }
    },
  )
}

///|
async test "README async parallel smoke test" {
  let commands = @qsm.ParallelCommands::{
    prefix: @qsm.Commands::empty(),
    left: @qsm.Commands::{ commands: [demo_command(DemoIncr, DemoUnit)], },
    right: @qsm.Commands::{ commands: [demo_command(DemoGet, DemoValue(0))], },
  }
  match
    @async_parallel.run_parallel_commands_async(demo_spec(), commands, config={
      seed: 1,
      cases: 1,
      max_commands: 4,
      size: 4,
      max_tries: 10,
      shrink: false,
      max_shrinks: 0,
      max_shrink_rounds: 0,
      required_labels: [],
      required_command_names: [],
    }) {
    Ok(report) => assert_eq(report.commands_run, 2)
    Err(failure) =>
      fail("unexpected async parallel failure: \{@debug.to_string(failure)}")
  }
}
```

## Core Concepts

`AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S]` uses the same
type parameters as the synchronous `StateMachine`:

- `MSym` is the pure symbolic model used during generation;
- `MCon` is the pure concrete model used during execution;
- `CSym` is the generated symbolic command;
- `CCon` is the real command executed after reification with the environment;
- `RSym` is the symbolic response predicted by `mock`;
- `RCon` is the real response returned by the system under test;
- `V` is the type of real values that symbolic variables are eventually bound
  to;
- `S` is the system under test, created once per test case.

The symbolic and concrete models may use the same type or different types. The
same is true for commands and responses. `CSym` and `CCon` often differ when a
command contains `Ref::Symbolic(var)`, handles, temporary ids, or other values
that need runtime substitution.

## Constructing AsyncStateMachine

When using `AsyncStateMachine::new`, the required callbacks describe one full
state machine path:

- `init_symbolic_model`: the initial model before commands are generated;
- `init_concrete_model`: the initial model before commands are replayed;
- `init_system`: creates the system under test, once per case;
- `generator`: generates the next symbolic command from the symbolic model,
  size, and random state; return `None` to end the program normally;
- `mock`: predicts the response without executing the real system, and uses
  `GenSym::fresh` to create new `Var`s when needed;
- `transition_symbolic`: advances the generation model from the symbolic command
  and symbolic response;
- `transition_concrete`: advances the execution model from the real command and
  real response;
- `reify_command`: uses `Environment[V]` to replace symbolic variables in a
  command with real values;
- `run_command`: executes the real command asynchronously;
- `bind_response`: binds values from the real response back to variables
  predicted by `mock`.

Only `init_system`, `run_command`, and `cleanup` are async callbacks.
`generator`, `mock`, model transitions, preconditions, postconditions, variable
binding, and invariants should still be pure, deterministic, and fast. MoonBit
has no `await` keyword. A function or test that calls async functions should be
declared as `async fn` or `async test`.

The optional callbacks have permissive defaults:

- `precondition`, `postcondition`, and `invariant` always hold by default;
- `response_vars` returns no new variables by default;
- `shrinker` produces no shrink candidates by default;
- `remap_command` leaves commands unchanged by default;
- `cleanup` does nothing by default;
- `command_name` returns `"command"` by default;
- `label` produces no coverage labels by default.

If commands refer to variables introduced by earlier responses, you usually
need to implement `response_vars`, `reify_command`, and `bind_response`. If you
support shrinking or parallel splitting, you also need a correct
`remap_command`.

## Entry Points

`run_parallel_commands_async(spec, commands, config?)`

Runs an already-built `ParallelCommands` value. Use it to replay regression
cases, minimized counterexamples, or manually constructed interleavings. The
execution order is:

1. execute `commands.prefix` sequentially;
2. run `commands.left` and `commands.right` concurrently on the same `S`, using
   two async tasks;
3. merge the environment deltas produced by the two branches;
4. check the invocation/response history from the concurrent branches for
   linearizability;
5. call `cleanup`, then produce a `RunReport` or return an `AsyncRunFailure`.

`check_parallel_async(spec, config?)`

Generates and runs multiple sets of parallel commands according to
`config.cases`. Each case uses `config.seed + case_index` as its seed. On
success, it returns the commands, history, and labels from the last case, while
`cases_run` and `commands_run` summarize all cases.

The current async parallel runner does not shrink failing cases. `shrinks` and
`shrink_rounds` in failures are always `0`. `shrinker` remains part of the
specification to keep the shape aligned with the synchronous API and to leave
room for async parallel shrinking in the future.

`assert_check_parallel_async(spec, config?)`

This is a test convenience wrapper around `check_parallel_async`. It returns
`RunReport` on success and calls `fail` on failure. Because the failure message
uses `@debug.to_string`, the model, command, and response types need to
implement `Debug`.

`AsyncStateMachine::from_sync(spec)`

Lifts a synchronous `StateMachine` into an async specification. This entry point
is useful when reusing an existing model. MoonBit async scheduling is
cooperative. If the synchronous `run_command` has no suspension point, commands
from the two branches still execute as atomic fragments in practice and do not
automatically create real interleavings. To test real races, `run_command`
should call async I/O, `@async.pause()`, or another async operation that yields
execution.

## ParallelCommands Semantics

`ParallelCommands` comes from the root package and has this shape:

```text
prefix : Commands[CSym, RSym]
left   : Commands[CSym, RSym]
right  : Commands[CSym, RSym]
```

`prefix` is the setup phase and is executed strictly in sequence. `left` and
`right` are concurrent suffixes. The runner assigns a stable `Pid` to each
command: prefix commands start at `0`, left commands follow the prefix, and
right commands follow the left branch. The history records `Invocation`,
`Response`, and, when execution raises, `Exception`.

In generation mode, the package first generates a sequential command sequence.
It then takes the first half as the prefix, chooses up to 6 commands from the
remaining sequence as the concurrent chunk, and splits that chunk evenly into
left and right. A command may enter the concurrent chunk only when:

- it can be remapped under the variable scope already provided by the prefix;
- every permutation of the concurrent chunk satisfies `precondition`;
- the number of response variables produced by `mock` is the same under every
  permutation as in the original recorded command;
- the command does not depend on variables newly produced by another command in
  the same chunk.

Manually constructed `ParallelCommands` values should follow the same
constraints. In particular, one branch cannot read a variable created by the
other branch, because both branches start from a copy of the environment at the
end of the prefix.

## Linearization Check

After both concurrent branches complete, the runner checks whether the history
can be linearized. It does not pin the order to the real completion order. The
linearization search:

- preserves real-time order: if one operation's response appears before another
  operation's invocation, the second operation cannot be ordered before the
  first;
- applies `postcondition`, `transition_concrete`, and `invariant` to each
  candidate operation in order;
- succeeds as soon as it finds one complete valid order;
- returns `LinearizationFailed` if every possible order fails, with `logic`
  containing the aggregated failure explanation.

To avoid unbounded factorial search, the concurrent suffix may contain at most
6 operations. If a manually supplied value contains more operations,
`run_parallel_commands_async` returns `LinearizationBudgetExceeded` before
calling `init_system`.

## Environment And Variable Binding

`Environment[V]` stores `Var -> V` bindings. The prefix executes sequentially
and keeps updating one base environment. When the concurrent phase starts, left
and right each receive a copy of that base environment. New variables produced
during a branch exist only in that branch's environment. After both branches
finish, the runner computes each branch's delta relative to the base environment
and merges the deltas:

- if the branches bind different new variables, the merge succeeds;
- if a branch binds an existing variable again, or if both branches bind the
  same new variable, the merge fails with `BranchEnvironmentMergeFailed`;
- if one branch needs to read a variable created by the other branch, reification
  fails because the variable is missing, and the failure is wrapped as
  `ReplayFailed(... ReifyFailed ...)`.

`mock` and `response_vars` must agree. If `mock` predicts some number of
variables, `response_vars` must return those variables in the same order.
`bind_response` inserts values from the real response into the environment.

## Failure Types

`AsyncRunFailure` contains async-parallel-specific failures and also reuses the
root package's `RunFailure`:

- `ReplayFailed(parallel_commands?, failure)`: ordinary generation,
  initialization, prefix execution, branch execution, reification, binding,
  cleanup, coverage, and related failures. `failure` is the root package
  `RunFailure`. `parallel_commands` may be `None` when the failure happens
  during generation or configuration validation;
- `LinearizationFailed(...)`: the real concurrent history cannot be explained by
  any valid sequential order;
- `LinearizationBudgetExceeded(...)`: the concurrent suffix contains more
  operations than the current linearization budget allows;
- `BranchEnvironmentMergeFailed(...)`: the left/right environment deltas cannot
  be merged.

When investigating a failure, check `history` first. It tells you when each
command was invoked, when it returned, and whether an exception happened during
real execution.

## Notes

- `run_command` must describe the real system behavior. Do not update the model
  there. The model should only be updated through `transition_concrete`.
- `postcondition` receives the model from before the current command executes.
  Use `invariant` for global constraints that describe the state after
  execution.
- `cleanup` errors on the success path return
  `ReplayFailed(... CleanupFailed ...)`. Cleanup errors on the failure path are
  ignored so they do not hide the original failure.
- Coverage checks run after semantic checks and successful cleanup. Missing
  `required_labels` or `required_command_names` returns
  `ReplayFailed(... CoverageFailed ...)`.
- `config.max_commands` controls the maximum generated sequential command
  count. The concurrent linearization budget is separately fixed at 6 suffix
  operations.
- Exposing concurrent bugs requires the operations under test to really yield
  execution. Pure synchronous computation wrapped by the async runner usually
  still executes as atomic fragments under task scheduling.
