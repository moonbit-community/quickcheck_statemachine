///|
enum CounterCommand {
  CounterIncr
  CounterGet
} derive(Eq, Debug)

///|
enum CounterResponse {
  CounterUnit
  CounterValue(Int32)
} derive(Eq, Debug)

///|
struct CounterSystem {
  mut value : Int32
  mut reads : Int32
  mut completed : Int32
}

///|
fn counter_expected(model : Int32, command : CounterCommand) -> CounterResponse {
  match command {
    CounterIncr => CounterUnit
    CounterGet => CounterValue(model)
  }
}

///|
fn counter_transition(
  model : Int32,
  command : CounterCommand,
  response : CounterResponse,
) -> Int32 {
  ignore(response)
  match command {
    CounterIncr => model + 1
    CounterGet => model
  }
}

///|
fn counter_command(
  command : CounterCommand,
) -> @qsm.Command[CounterCommand, CounterResponse] {
  @qsm.Command::{ command, response: CounterUnit, vars: [], }
}

///|
fn counter_commands(
  commands : Array[CounterCommand],
) -> @qsm.Commands[CounterCommand, CounterResponse] {
  let items : Array[@qsm.Command[CounterCommand, CounterResponse]] = []
  for command in commands {
    items.push(counter_command(command))
  }
  @qsm.Commands::{ commands: items, }
}

///|
fn counter_parallel(
  prefix : Array[CounterCommand],
  left : Array[CounterCommand],
  right : Array[CounterCommand],
) -> @qsm.ParallelCommands[CounterCommand, CounterResponse] {
  @qsm.ParallelCommands::{
    prefix: counter_commands(prefix),
    left: counter_commands(left),
    right: counter_commands(right),
  }
}

///|
fn counter_config() -> @qsm.RunConfig {
  {
    seed: 1,
    cases: 1,
    max_commands: 10,
    size: 10,
    max_tries: 10,
    shrink: false,
    max_shrinks: 0,
    max_shrink_rounds: 0,
    required_labels: [],
    required_command_names: [],
  }
}

///|
fn counter_spec(
  racy : Bool,
  initialized : Array[Bool],
) -> @async_parallel.AsyncStateMachine[
  Int32,
  Int32,
  CounterCommand,
  CounterCommand,
  CounterResponse,
  CounterResponse,
  Unit,
  CounterSystem,
] {
  @async_parallel.AsyncStateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => {
      initialized.push(true)
      { value: 0, reads: 0, completed: 0, }
    },
    generator=(_, _, _) => None,
    mock=(model, command, gen_sym) => {
      (counter_expected(model, command), gen_sym)
    },
    transition_symbolic=counter_transition,
    transition_concrete=counter_transition,
    reify_command=(command, _) => Ok(command),
    run_command=(command, system) => {
      match command {
        CounterIncr =>
          if racy {
            let old = system.value
            system.reads += 1
            while system.reads < 2 {
              @async.pause()
            }
            system.value = old + 1
            system.completed += 1
            CounterUnit
          } else {
            system.value += 1
            system.completed += 1
            CounterUnit
          }
        CounterGet => {
          while system.completed < 2 {
            @async.pause()
          }
          CounterValue(system.value)
        }
      }
    },
    bind_response=(_, _, environment) => Ok(environment),
    postcondition=(model, command, response) => {
      @qsm.Logic::predicate(
        name="counter response matches model",
        value=response == counter_expected(model, command),
      )
    },
  )
}

///|
fn sync_counter_spec(
  initialized : Array[Bool],
) -> @qsm.StateMachine[
  Int32,
  Int32,
  CounterCommand,
  CounterCommand,
  CounterResponse,
  CounterResponse,
  Unit,
  CounterSystem,
] {
  @qsm.StateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => {
      initialized.push(true)
      { value: 0, reads: 0, completed: 0, }
    },
    generator=(_, _, _) => None,
    mock=(model, command, gen_sym) => {
      (counter_expected(model, command), gen_sym)
    },
    transition_symbolic=counter_transition,
    transition_concrete=counter_transition,
    reify_command=(command, _) => Ok(command),
    run_command=(command, system) => {
      match command {
        CounterIncr => {
          system.value += 1
          CounterUnit
        }
        CounterGet => CounterValue(system.value)
      }
    },
    bind_response=(_, _, environment) => Ok(environment),
    postcondition=(model, command, response) => {
      @qsm.Logic::predicate(
        name="counter response matches model",
        value=response == counter_expected(model, command),
      )
    },
  )
}

///|
fn overlapping_invocations(
  history : @qsm.History[CounterCommand, CounterResponse],
) -> Int32 {
  for index = 0; index < history.events.length(); index = index + 1 {
    match history.events[index] {
      @qsm.Invocation(..) => ()
      _ => break index
    }
  } nobreak {
    history.events.length()
  }
}

///|
async test "from_sync runs prefix-only async parallel programs" {
  let initialized : Array[Bool] = []
  let commands = counter_parallel([CounterIncr, CounterGet], [], [])
  match
    @async_parallel.run_parallel_commands_async(
      @async_parallel.AsyncStateMachine::from_sync(
        sync_counter_spec(initialized),
      ),
      commands,
      config=counter_config(),
    ) {
    Ok(report) => {
      assert_eq(report.commands_run, 2)
      assert_eq(report.history.events.length(), 4)
      assert_eq(initialized.length(), 1)
    }
    _ => fail("expected from_sync prefix-only success")
  }
}

///|
async test "async parallel runner detects lost update linearization failure" {
  let initialized : Array[Bool] = []
  let commands = counter_parallel([], [CounterIncr, CounterGet], [CounterIncr])
  match
    @async_parallel.run_parallel_commands_async(
      counter_spec(true, initialized),
      commands,
      config=counter_config(),
    ) {
    Err(@async_parallel.LinearizationFailed(history~, ..)) =>
      assert_true(overlapping_invocations(history) >= 2)
    _ => fail("expected linearization failure")
  }
}

///|
async test "faithful async counter parallel run succeeds" {
  let initialized : Array[Bool] = []
  let commands = counter_parallel([], [CounterIncr, CounterGet], [CounterIncr])
  match
    @async_parallel.run_parallel_commands_async(
      counter_spec(false, initialized),
      commands,
      config=counter_config(),
    ) {
    Ok(report) => {
      assert_eq(report.commands_run, 3)
      assert_eq(initialized.length(), 1)
    }
    _ => fail("expected faithful counter success")
  }
}

///|
async test "parallel budget failure happens before init_system" {
  let initialized : Array[Bool] = []
  let commands = counter_parallel(
    [],
    [CounterIncr, CounterIncr, CounterIncr, CounterIncr],
    [CounterIncr, CounterIncr, CounterIncr],
  )
  match
    @async_parallel.run_parallel_commands_async(
      counter_spec(false, initialized),
      commands,
      config=counter_config(),
    ) {
    Err(
      @async_parallel.LinearizationBudgetExceeded(
        history~,
        operation_count~,
        max_operations~,
        ..
      )
    ) => {
      assert_eq(operation_count, 7)
      assert_eq(max_operations, 6)
      assert_eq(history.events.length(), 0)
      assert_eq(initialized.length(), 0)
    }
    _ => fail("expected budget failure")
  }
}

///|
enum DupCommand {
  DupMake
} derive(Eq, Debug)

///|
enum DupResponse {
  DupMade(@qsm.Var)
} derive(Eq, Debug)

///|
fn dup_commands(variable : @qsm.Var) -> @qsm.Commands[DupCommand, DupResponse] {
  @qsm.Commands::{
    commands: [
      @qsm.Command::{
        command: DupMake,
        response: DupMade(variable),
        vars: [variable],
      },
    ],
  }
}

///|
fn dup_spec() -> @async_parallel.AsyncStateMachine[
  Unit,
  Unit,
  DupCommand,
  DupCommand,
  DupResponse,
  DupResponse,
  Unit,
  Unit,
] {
  @async_parallel.AsyncStateMachine::new(
    init_symbolic_model=() => (),
    init_concrete_model=() => (),
    init_system=() => (),
    generator=(_, _, _) => None,
    mock=(_, _, gen_sym) => (DupMade(@qsm.Var::{ id: 0, }), gen_sym),
    transition_symbolic=(_, _, _) => (),
    transition_concrete=(_, _, _) => (),
    reify_command=(command, _) => Ok(command),
    run_command=(_, _) => DupMade(@qsm.Var::{ id: 0, }),
    bind_response=(symbolic, _, environment) => {
      match symbolic {
        DupMade(variable) => Ok(environment.insert(variable, ()))
      }
    },
  )
}

///|
async test "duplicate branch environments are reported separately" {
  let variable = @qsm.Var::{ id: 0, }
  let commands = @qsm.ParallelCommands::{
    prefix: @qsm.Commands::empty(),
    left: dup_commands(variable),
    right: dup_commands(variable),
  }
  match
    @async_parallel.run_parallel_commands_async(
      dup_spec(),
      commands,
      config=counter_config(),
    ) {
    Err(@async_parallel.BranchEnvironmentMergeFailed(error~, ..)) =>
      assert_true(error is @qsm.DuplicateVar(_))
    _ => fail("expected branch environment merge failure")
  }
}
