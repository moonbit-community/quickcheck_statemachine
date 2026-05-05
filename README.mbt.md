# moonbit-community/quickcheck_statemachine

`quickcheck_statemachine` is a program-based state-machine testing library for
MoonBit. A test first generates a complete symbolic command program, then
executes it against a mutable system by reifying symbolic references through an
execution environment.

## Quick Start

```mbt check
///|
enum ReadmeCommand {
  Add(Int)
  Get
} derive(Eq, Debug)

///|
enum ReadmeResponse {
  Added
  Got(Int)
} derive(Eq, Debug)

///|
struct ReadmeCounter {
  mut value : Int
} derive(Eq, Debug)

///|
fn readme_expected(model : Int, command : ReadmeCommand) -> ReadmeResponse {
  match command {
    Add(_) => Added
    Get => Got(model)
  }
}

///|
test {
  let script : Array[ReadmeCommand] = [Add(1), Get, Add(2), Get]
  let cursor : Array[Int] = [0]
  let spec : @quickcheck_statemachine.StateMachine[
    Int,
    Int,
    ReadmeCommand,
    ReadmeCommand,
    ReadmeResponse,
    ReadmeResponse,
    Unit,
    ReadmeCounter,
  ] = @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => ReadmeCounter::{ value: 0 },
    generator=(model, size, rng) => {
      ignore(model)
      ignore(size)
      ignore(rng)
      let index = cursor[0]
      if index < script.length() {
        cursor[0] = index + 1
        Some(script[index])
      } else {
        None
      }
    },
    mock=(model, command, gen_sym) => (readme_expected(model, command), gen_sym),
    transition_symbolic=(model, command, response) => {
      ignore(response)
      match command {
        Add(n) => model + n
        Get => model
      }
    },
    transition_concrete=(model, command, response) => {
      ignore(response)
      match command {
        Add(n) => model + n
        Get => model
      }
    },
    reify_command=(command, environment) => {
      ignore(environment)
      Ok(command)
    },
    run_command=(command, system) => {
      match command {
        Add(n) => {
          system.value = system.value + n
          Added
        }
        Get => Got(system.value)
      }
    },
    bind_response=(symbolic, concrete, environment) => {
      ignore(symbolic)
      ignore(concrete)
      Ok(environment)
    },
    postcondition=(model, command, response) => {
      @quickcheck_statemachine.Logic::boolean(
        response == readme_expected(model, command),
      )
    },
  )
  let summary = @quickcheck_statemachine.assert_check(spec, config=@quickcheck_statemachine.RunConfig::{
    seed: 7,
    cases: 1,
    max_commands: script.length(),
    size: script.length(),
    max_tries: 10,
    shrink: true,
    max_shrinks: 20,
    max_shrink_rounds: 10,
    required_labels: [],
    required_command_names: [],
  })
  assert_eq(summary.commands_run, 4)
}
```

## Core Pieces

- `Logic` carries diagnostic precondition, postcondition, and invariant results.
- `Var`, `Ref[V]`, `GenSym`, and `Environment[V]` model symbolic references and
  their concrete bindings.
- `generate_commands` produces a `Commands[CSym, RSym]` program without touching
  the system under test.
- `run_commands`, `check`, and `replay` execute an existing program and return a
  `RunReport` or structured `RunFailure`.
- `shrink_commands_once` and the `check` loop perform dependency-aware shrinking
  by remapping symbolic variables through `remap_command`.

Symbolic handles are explicit in MoonBit: user code defines a concrete value
union, reifies `Ref[V]` values through `Environment[V]`, and binds response
variables in `bind_response`.
