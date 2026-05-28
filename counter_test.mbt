///|
// Counter model and property:
// The model is the single integer value that a correct mutable counter should
// contain after each prefix of the command program. `CounterIncr` advances that
// model by one, while `CounterGet` observes it. The property under test is the
// basic state-machine lockstep property from the blogs: after each concrete
// command, the observed response must match the response predicted by the pure
// model.
fn case_config(
  max_commands~ : Int,
  cases? : Int = 1,
  max_tries? : Int = 10,
  shrink? : Bool = true,
  required_labels? : Array[String] = [],
  required_command_names? : Array[String] = [],
) -> @quickcheck_statemachine.RunConfig {
  {
    seed: 20240702,
    cases,
    max_commands,
    size: max_commands,
    max_tries,
    shrink,
    max_shrinks: 100,
    max_shrink_rounds: 20,
    required_labels,
    required_command_names,
  }
}

///|
enum CounterCommand {
  CounterIncr
  CounterGet
} derive(Eq, Debug)

///|
enum CounterResponse {
  CounterIncrDone
  CounterGot(Int)
} derive(Eq, Debug)

///|
struct CounterSystem {
  mut value : Int
} derive(Eq, Debug)

///|
fn run_counter_command(
  command : CounterCommand,
  system : CounterSystem,
) -> CounterResponse {
  match command {
    CounterIncr => {
      system.value += 1
      CounterIncrDone
    }
    CounterGet => CounterGot(system.value)
  }
}

///|
fn run_counter_with_42_bug(
  command : CounterCommand,
  system : CounterSystem,
) -> CounterResponse {
  match command {
    CounterIncr => {
      if system.value != 42 {
        system.value += 1
      }
      CounterIncrDone
    }
    CounterGet => CounterGot(system.value)
  }
}

///|
fn counter_transition(model : Int, command : CounterCommand) -> Int {
  match command {
    CounterIncr => model + 1
    CounterGet => model
  }
}

///|
fn counter_expected(model : Int, command : CounterCommand) -> CounterResponse {
  match command {
    CounterIncr => CounterIncrDone
    CounterGet => CounterGot(model)
  }
}

///|
fn counter_name(command : CounterCommand) -> String {
  match command {
    CounterIncr => "incr"
    CounterGet => "get"
  }
}

///|
fn counter_script_spec(
  commands : Array[CounterCommand],
  run_command? : (CounterCommand, CounterSystem) -> CounterResponse = run_counter_command,
) -> @quickcheck_statemachine.StateMachine[
  Int,
  Int,
  CounterCommand,
  CounterCommand,
  CounterResponse,
  CounterResponse,
  Unit,
  CounterSystem,
] {
  let cursor : Array[Int] = [0]
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => { value: 0 },
    generator=(model, size, rng) => {
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
    },
    mock=(model, command, gen_sym) => {
      (counter_expected(model, command), gen_sym)
    },
    transition_symbolic=(model, command, response) => {
      ignore(response)
      counter_transition(model, command)
    },
    transition_concrete=(model, command, response) => {
      ignore(response)
      counter_transition(model, command)
    },
    reify_command=(command, environment) => {
      ignore(environment)
      Ok(command)
    },
    run_command=(command, system) => run_command(command, system),
    bind_response=(symbolic, concrete, environment) => {
      ignore(symbolic)
      ignore(concrete)
      Ok(environment)
    },
    postcondition=(model, command, response) => {
      @quickcheck_statemachine.Logic::predicate(
        name="counter response matches model",
        value=response == counter_expected(model, command),
      )
    },
    command_name=counter_name,
  )
}

///|
fn counter_increments_then_get(count : Int) -> Array[CounterCommand] {
  let commands : Array[CounterCommand] = []
  for _ in 0..<count {
    commands.push(CounterIncr)
  }
  commands.push(CounterGet)
  commands
}

///|
// Faithful implementation regression:
// This script exercises both command names and checks that generation,
// execution, transition, and postcondition stay in lockstep for a small program.
// It is the positive contract test for the fake/model: the real counter and the
// model should agree after every prefix.
test "counter passes against faithful implementation" {
  let commands : Array[CounterCommand] = [
    CounterIncr,
    CounterGet,
    CounterIncr,
    CounterGet,
  ]
  let summary = @quickcheck_statemachine.assert_check(
    counter_script_spec(commands),
    config=case_config(max_commands=commands.length()),
  )
  assert_eq(summary.cases_run, 1)
  assert_eq(summary.commands_run, 4)
  assert_eq(summary.command_distribution.length(), 2)
}

///|
// Bug-finding regression:
// This mirrors the counter examples used to motivate stateful property tests:
// a long prefix can move the implementation into a state where a later
// observation reveals the bug. The implementation stops incrementing at 42, but
// the pure model reaches 43; the `Get` response therefore violates the
// postcondition while the transition model itself remains deterministic.
test "counter catches value 42 increment bug" {
  let commands = counter_increments_then_get(43)
  let result = @quickcheck_statemachine.check(
    counter_script_spec(commands, run_command=run_counter_with_42_bug),
    config=case_config(max_commands=commands.length()),
  )
  guard result
    is Err(
      PostconditionFailed(
        step_index~,
        command~,
        response~,
        model~,
        next_model~,
        commands~,
        ..
      )
    ) else {
    fail("expected counter postcondition failure")
  }
  assert_eq(step_index, 43)
  assert_true(command is CounterGet)
  assert_true(response is CounterGot(42))
  assert_eq(model, 43)
  assert_eq(next_model, 43)
  assert_eq(commands.length(), 44)
}
