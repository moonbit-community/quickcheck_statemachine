# moonbit-community/quickcheck_statemachine

`quickcheck_statemachine` is a MoonBit library for testing stateful programs
with model-based properties. Instead of checking one operation at a time, a test
generates a whole program of commands, executes it against a mutable system, and
checks every response against a pure model.

This library is useful when:

- valid operations depend on earlier operations;
- a bug only appears after a sequence of commands;
- the implementation has handles, ids, files, queues, counters, or other mutable
  state that is awkward to test with single examples.

## How It Works

A state-machine test has these pieces:

- `Command`: operations that can be generated.
- `Response`: observable results returned by the system.
- `Model`: a pure description of what should be true after each command.
- `precondition`: when a generated command is valid.
- `transition`: how the model changes after a command and response.
- `postcondition`: what must hold after running a command.
- `generator` and `shrinker`: how command programs are generated and minimized.
- `mock`: symbolic responses used while generating and shrinking.
- `reify_command` and `bind_response`: how symbolic references become concrete
  values during execution.
- `run_command`: the real implementation under test.

The sequential property first builds a complete symbolic command program:

1. Start with the initial symbolic model and a fresh symbolic-variable supply.
2. Ask the generator for a command and keep retrying until the precondition
   accepts it, or the retry budget is exhausted.
3. Ask `mock` for the symbolic response and record any variables introduced by
   that response.
4. Advance the symbolic model with the symbolic transition.
5. Repeat until `max_commands` is reached or the generator stops.

The generated program is then replayed against the concrete system:

1. Start with the initial concrete model, initial system, empty environment, and
   empty history.
2. Reify symbolic references into concrete references using the environment.
3. Execute the command against the system and record invocation/response
   history.
4. Check the postcondition against the pre-state model and observed response.
5. Bind any new concrete references returned by the response.
6. Advance the concrete model, check the invariant, and collect labels.
7. After the program finishes, run cleanup and coverage checks.

When `check` finds a semantic failure and `shrink` is enabled, it shrinks the
generated command program and reports a smaller counterexample. Direct
`run_commands` and `replay` calls execute the supplied program as-is.

## Example: Mutable References

As a first example, consider a tiny mutable-reference system. A program can
create a reference, read it, write it, and increment it. The implementation below
also has an optional logic bug: writing a value in `5..=10` stores `value + 1`
instead.

### Commands And Responses

Generated programs cannot contain real references before execution starts.
Commands therefore use `Ref[RefId]`: symbolic references during generation, and
concrete references when the program is executed.

```moonbit nocheck
///|
struct RefId {
  id : Int
} derive(Eq, Debug)

///|
enum Command {
  Create
  Read(@quickcheck_statemachine.Ref[RefId])
  Write(@quickcheck_statemachine.Ref[RefId], Int)
  Increment(@quickcheck_statemachine.Ref[RefId])
} derive(Eq, Debug)

///|
enum Response {
  Created(@quickcheck_statemachine.Ref[RefId])
  ReadValue(Int)
  Written
  Incremented
} derive(Eq, Debug)
```

`Create` returns a reference, so its response may introduce a new symbolic
variable. Later commands can mention that variable; during execution it will be
looked up in the environment and replaced by the concrete `RefId`.

### The System Under Test

The implementation stores references in a mutable array. The `Bug` parameter is
there only to demonstrate that the property can find a bad implementation.

```moonbit nocheck
///|
enum Bug {
  NoBug
  LogicBug
} derive(Eq, Debug)

///|
struct SystemEntry {
  id : Int
  value : Int
} derive(Eq, Debug)

///|
struct ReferenceSystem {
  refs : Array[SystemEntry]
  mut next_id : Int
} derive(Eq, Debug)
```

The helper functions are ordinary system operations. They only deal with
concrete ids.

```moonbit nocheck
///|
fn reference_id(reference : @quickcheck_statemachine.Ref[RefId]) -> Int? {
  match reference {
    Concrete(ref_id) => Some(ref_id.id)
    Symbolic(_) => None
  }
}

///|
fn system_lookup(system : ReferenceSystem, id : Int) -> Int? {
  for entry in system.refs {
    if entry.id == id {
      return Some(entry.value)
    }
  }
  None
}

///|
fn system_update(system : ReferenceSystem, id : Int, value : Int) -> Unit {
  for index = 0; index < system.refs.length(); {
    if system.refs[index].id == id {
      system.refs[index] = { id, value }
      return
    }
    continue index + 1
  }
}
```

`semantics` is the real command interpreter. In a larger test this is where you
would call a database, file system, service, or mutable data structure.

```moonbit nocheck
///|
fn semantics(
  bug : Bug,
  command : Command,
  system : ReferenceSystem,
) -> Response {
  match command {
    Create => {
      let id = system.next_id
      system.next_id += 1
      system.refs.push({ id, value: 0 })
      Created(Concrete({ id, }))
    }
    Read(reference) =>
      match reference_id(reference) {
        Some(id) =>
          match system_lookup(system, id) {
            Some(value) => ReadValue(value)
            None => ReadValue(0)
          }
        None => ReadValue(0)
      }
    Write(reference, value) =>
      match reference_id(reference) {
        Some(id) => {
          let stored = if bug == LogicBug && 5 <= value && value <= 10 {
            value + 1
          } else {
            value
          }
          system_update(system, id, stored)
          Written
        }
        None => Written
      }
    Increment(reference) =>
      match reference_id(reference) {
        Some(id) => {
          match system_lookup(system, id) {
            Some(value) => system_update(system, id, value + 1)
            None => ()
          }
          Incremented
        }
        None => Incremented
      }
  }
}
```

### The Model

The model is pure data. It says which references exist and what value each
reference should contain.

```moonbit nocheck
///|
struct ModelEntry {
  reference : @quickcheck_statemachine.Ref[RefId]
  value : Int
} derive(Eq, Debug)

///|
struct Model {
  refs : Array[ModelEntry]
} derive(Eq, Debug)

///|
fn model_empty() -> Model {
  { refs: [] }
}
```

The model helpers are deliberately simple. They are not the implementation under
test; they are the specification used to check it.

```moonbit nocheck
///|
fn model_lookup(
  model : Model,
  reference : @quickcheck_statemachine.Ref[RefId],
) -> Int? {
  for entry in model.refs {
    if entry.reference == reference {
      return Some(entry.value)
    }
  }
  None
}

///|
fn model_member(
  model : Model,
  reference : @quickcheck_statemachine.Ref[RefId],
) -> Bool {
  model_lookup(model, reference) is Some(_)
}

///|
fn model_update(
  model : Model,
  reference : @quickcheck_statemachine.Ref[RefId],
  value : Int,
) -> Model {
  let refs = model.refs.copy()
  for index = 0; index < refs.length(); {
    if refs[index].reference == reference {
      refs[index] = { reference, value }
      return { refs, }
    }
    continue index + 1
  }
  refs.push({ reference, value })
  { refs, }
}
```

### Preconditions And Transitions

The precondition is the client contract. `Create` is always valid. Reads,
writes, and increments are valid only for references that are already present in
the model.

```moonbit nocheck
///|
fn precondition(
  model : Model,
  command : Command,
) -> @quickcheck_statemachine.Logic {
  let ok = match command {
    Create => true
    Read(reference) | Write(reference, _) | Increment(reference) =>
      model_member(model, reference)
  }
  @quickcheck_statemachine.Logic::predicate(name="known reference", value=ok)
}
```

The transition function advances the pure model. It is used both while
generating symbolic programs and while checking concrete executions.

```moonbit nocheck
///|
fn transition(model : Model, command : Command, response : Response) -> Model {
  match (command, response) {
    (Create, Created(reference)) => model_update(model, reference, 0)
    (Read(_), ReadValue(_)) => model
    (Write(reference, value), Written) => model_update(model, reference, value)
    (Increment(reference), Incremented) =>
      match model_lookup(model, reference) {
        Some(value) => model_update(model, reference, value + 1)
        None => model
      }
    _ => model
  }
}
```

### Postconditions

Postconditions compare the concrete system response with the model. A `Read`
must return the current modeled value. A `Create` must create a reference whose
initial modeled value is zero.

```moonbit nocheck
///|
fn postcondition(
  model : Model,
  command : Command,
  response : Response,
) -> @quickcheck_statemachine.Logic {
  match (command, response) {
    (Create, Created(reference)) => {
      let next_model = transition(model, command, response)
      @quickcheck_statemachine.Logic::predicate(
        name="Create",
        value=model_lookup(next_model, reference) == Some(0),
      )
    }
    (Read(reference), ReadValue(value)) =>
      @quickcheck_statemachine.Logic::predicate(
        name="Read",
        value=model_lookup(model, reference) == Some(value),
      )
    (Write(_, _), Written) => @quickcheck_statemachine.Logic::top()
    (Increment(_), Incremented) => @quickcheck_statemachine.Logic::top()
    _ => @quickcheck_statemachine.Logic::bot()
  }
}
```

### Generation And Shrinking

The generator creates commands from the current symbolic model. If there are no
references yet, it must create one first. Once references exist, it can generate
any valid operation over one of them.

```moonbit nocheck
///|
fn choose_reference(
  model : Model,
  rng : @splitmix.RandomState,
) -> @quickcheck_statemachine.Ref[RefId] {
  let index = rng.next_positive_int() % model.refs.length()
  model.refs[index].reference
}

///|
fn generator(
  model : Model,
  size : Int,
  rng : @splitmix.RandomState,
) -> Command? {
  ignore(size)
  if model.refs.length() == 0 {
    Some(Create)
  } else {
    match rng.next_positive_int() % 4 {
      0 => Some(Create)
      1 => Some(Read(choose_reference(model, rng)))
      2 =>
        Some(Write(choose_reference(model, rng), rng.next_positive_int() % 16))
      _ => Some(Increment(choose_reference(model, rng)))
    }
  }
}
```

The shrinker tries smaller writes. The library also performs dependency-aware
command deletion and remaps symbolic variables when possible.

```moonbit nocheck
///|
fn shrinker(_model : Model, command : Command) -> Array[Command] {
  match command {
    Write(reference, value) =>
      if value == 0 {
        []
      } else {
        [Write(reference, 0), Write(reference, value / 2)]
      }
    _ => []
  }
}
```

### Symbolic Responses

`mock` predicts symbolic responses during generation and shrinking. For `Create`
it allocates a fresh symbolic variable. For `Read` it returns the value from the
model. For `Write` and `Increment` it can return simple acknowledgements.

```moonbit nocheck
///|
fn mock(
  model : Model,
  command : Command,
  gen_sym : @quickcheck_statemachine.GenSym,
) -> (Response, @quickcheck_statemachine.GenSym) {
  match command {
    Create => {
      let (fresh_var, next_gen_sym) = gen_sym.fresh()
      (Created(Symbolic(fresh_var)), next_gen_sym)
    }
    Read(reference) =>
      match model_lookup(model, reference) {
        Some(value) => (ReadValue(value), gen_sym)
        None => (ReadValue(0), gen_sym)
      }
    Write(_, _) => (Written, gen_sym)
    Increment(_) => (Incremented, gen_sym)
  }
}

///|
fn response_vars(response : Response) -> Array[@quickcheck_statemachine.Var] {
  match response {
    Created(Symbolic(fresh_var)) => [fresh_var]
    _ => []
  }
}
```

Before execution, symbolic references must be reified into concrete references
using the environment built from earlier responses.

```moonbit nocheck
///|
fn reify_ref(
  reference : @quickcheck_statemachine.Ref[RefId],
  environment : @quickcheck_statemachine.Environment[RefId],
) -> Result[
  @quickcheck_statemachine.Ref[RefId],
  @quickcheck_statemachine.EnvError,
] {
  match reference {
    Concrete(ref_id) => Ok(Concrete(ref_id))
    Symbolic(fresh_var) =>
      match environment.lookup(fresh_var) {
        Ok(ref_id) => Ok(Concrete(ref_id))
        Err(error) => Err(error)
      }
  }
}

///|
fn reify_command(
  command : Command,
  environment : @quickcheck_statemachine.Environment[RefId],
) -> Result[Command, @quickcheck_statemachine.EnvError] {
  match command {
    Create => Ok(Create)
    Read(reference) =>
      match reify_ref(reference, environment) {
        Ok(concrete) => Ok(Read(concrete))
        Err(error) => Err(error)
      }
    Write(reference, value) =>
      match reify_ref(reference, environment) {
        Ok(concrete) => Ok(Write(concrete, value))
        Err(error) => Err(error)
      }
    Increment(reference) =>
      match reify_ref(reference, environment) {
        Ok(concrete) => Ok(Increment(concrete))
        Err(error) => Err(error)
      }
  }
}
```

After execution, a symbolic `Created` response must be bound to the concrete
reference returned by the system.

```moonbit nocheck
///|
fn bind_response(
  symbolic : Response,
  concrete : Response,
  environment : @quickcheck_statemachine.Environment[RefId],
) -> Result[
  @quickcheck_statemachine.Environment[RefId],
  @quickcheck_statemachine.BindError,
] {
  match (symbolic, concrete) {
    (Created(Symbolic(fresh_var)), Created(Concrete(ref_id))) =>
      Ok(environment.insert(fresh_var, ref_id))
    (Created(Symbolic(_)), _) => Err(BindMessage("expected concrete reference"))
    _ => Ok(environment)
  }
}
```

When shrinking removes commands, references may need to be rewritten. Returning
`None` means a candidate command is no longer valid because it depends on a
reference that disappeared.

```moonbit nocheck
///|
fn remap_ref(
  reference : @quickcheck_statemachine.Ref[RefId],
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> @quickcheck_statemachine.Ref[RefId]? {
  match reference {
    Concrete(ref_id) => Some(Concrete(ref_id))
    Symbolic(fresh_var) =>
      match scope.get(fresh_var) {
        Some(next_var) => Some(Symbolic(next_var))
        None => None
      }
  }
}

///|
fn remap_command(
  command : Command,
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> Command? {
  match command {
    Create => Some(Create)
    Read(reference) =>
      match remap_ref(reference, scope) {
        Some(next_reference) => Some(Read(next_reference))
        None => None
      }
    Write(reference, value) =>
      match remap_ref(reference, scope) {
        Some(next_reference) => Some(Write(next_reference, value))
        None => None
      }
    Increment(reference) =>
      match remap_ref(reference, scope) {
        Some(next_reference) => Some(Increment(next_reference))
        None => None
      }
  }
}
```

### Assembling The State Machine

All callbacks are packed into a `StateMachine`. The optional `script` parameter
below is just a test convenience: it lets the examples run a fixed command
program instead of random generation.

```moonbit nocheck
///|
fn command_name(command : Command) -> String {
  match command {
    Create => "create"
    Read(_) => "read"
    Write(_, _) => "write"
    Increment(_) => "increment"
  }
}

///|
fn config(
  max_commands~ : Int,
  shrink? : Bool = true,
) -> @quickcheck_statemachine.RunConfig {
  {
    seed: 11,
    cases: 1,
    max_commands,
    size: max_commands,
    max_tries: 20,
    shrink,
    max_shrinks: 20,
    max_shrink_rounds: 10,
    required_labels: [],
    required_command_names: [],
  }
}
```

```moonbit nocheck
///|
fn sm(
  bug : Bug,
  script? : Array[Command]? = None,
) -> @quickcheck_statemachine.StateMachine[
  Model,
  Model,
  Command,
  Command,
  Response,
  Response,
  RefId,
  ReferenceSystem,
] {
  let cursor : Array[Int] = [0]
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=model_empty,
    init_concrete_model=model_empty,
    init_system=() => { refs: [], next_id: 0 },
    generator=(model, size, rng) => {
      match script {
        Some(commands) => {
          ignore(model)
          ignore(size)
          ignore(rng)
          let index = cursor[0]
          if index < commands.length() {
            cursor[0] = index + 1
            Some(commands[index])
          } else {
            None
          }
        }
        None => generator(model, size, rng)
      }
    },
    mock~,
    transition_symbolic=transition,
    transition_concrete=transition,
    precondition~,
    postcondition~,
    response_vars~,
    shrinker~,
    remap_command~,
    reify_command~,
    run_command=(command, system) => semantics(bug, command, system),
    bind_response~,
    command_name~,
  )
}
```

### Running The Property

With the faithful implementation, the command program below passes.

```moonbit nocheck
///|
test "sequential property passes without the bug" {
  let reference : @quickcheck_statemachine.Ref[RefId] = Symbolic(@quickcheck_statemachine.Var::{
    id: 0,
  })
  let commands : Array[Command] = [
    Create,
    Write(reference, 4),
    Increment(reference),
    Read(reference),
  ]
  let report = @quickcheck_statemachine.assert_check(
    sm(NoBug, script=Some(commands)),
    config=config(max_commands=commands.length()),
  )
  assert_eq(report.commands_run, 4)
}
```

With the logic bug enabled, the same machinery finds a small counterexample:
create a reference, write `5`, then read it. The implementation returns `6`,
while the model expects `5`.

```moonbit nocheck
///|
test "sequential property finds the logic bug" {
  let reference : @quickcheck_statemachine.Ref[RefId] = Symbolic(@quickcheck_statemachine.Var::{
    id: 0,
  })
  let commands : Array[Command] = [Create, Write(reference, 5), Read(reference)]
  let result = @quickcheck_statemachine.check(
    sm(LogicBug, script=Some(commands)),
    config=config(max_commands=commands.length(), shrink=false),
  )
  guard result is Err(PostconditionFailed(step_index~, response~, logic~, ..)) else {
    fail("expected postcondition failure")
  }
  assert_eq(step_index, 2)
  assert_true(response is ReadValue(6))
  assert_true(!logic.eval())
}
```

## More Examples

The repository contains smaller focused examples:

- `counter_test.mbt` shows the smallest counter-style state machine.
- `queue_test.mbt` checks a mutable circular queue against a pure FIFO model.
- `filesystem_test.mbt` shows symbolic handles and label coverage diagnostics.
- `jug_test.mbt` uses a state machine as a search problem for the water-jug
  puzzle.
- `parallel_test.mbt` documents the current deterministic parallel command
  runner.

Replay is exposed through `replay`, `assert_replay`, and `run_saved_commands`;
the examples in this README use scripted generation with `assert_check`.

The Haskell library demonstrates concurrent race-condition testing. This
MoonBit package currently exposes `generate_parallel_commands`,
`ParallelCommands`, and `run_parallel_commands`, but the current runner
deterministically linearises commands as `prefix`, then `left`, then `right`.
It is not yet a full concurrent linearizability checker.
