///|
enum GenCommand {
  GenIncr
} derive(Eq, Debug)

///|
pub extend GenCommand with Eq::{not_equal, equal}

///|
pub extend GenCommand with Debug::{to_repr}

///|
enum GenResponse {
  GenUnit
} derive(Eq, Debug)

///|
pub extend GenResponse with Eq::{not_equal, equal}

///|
pub extend GenResponse with Debug::{to_repr}

///|
fn gen_config() -> @qsm.RunConfig {
  {
    seed: 11,
    cases: 1,
    max_commands: 20,
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
fn gen_spec() -> AsyncStateMachine[
  Int32,
  Int32,
  GenCommand,
  GenCommand,
  GenResponse,
  GenResponse,
  Unit,
  Unit,
] {
  AsyncStateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => (),
    generator=(model, _, _) => if model < 20 { Some(GenIncr) } else { None },
    mock=(_, _, gen_sym) => (GenUnit, gen_sym),
    transition_symbolic=(model, _, _) => model + 1,
    transition_concrete=(model, _, _) => model + 1,
    reify_command=(command, _) => Ok(command),
    run_command=(_, _) => GenUnit,
    bind_response=(_, _, environment) => Ok(environment),
  )
}

///|
test "async generation bounds parallel chunk" {
  match generate_parallel_commands_async_spec(gen_spec(), config=gen_config()) {
    Err(_) => fail("expected generated parallel commands")
    Ok(commands) => {
      let operation_count = commands.left.length() + commands.right.length()
      assert_true(operation_count <= 6)
      assert_true(
        commands.prefix.length() +
        commands.left.length() +
        commands.right.length() <=
        gen_config().max_commands,
      )
    }
  }
}

///|
enum DepCommand {
  DepPad
  DepMake
  DepUse(@qsm.Var)
} derive(Eq, Debug)

///|
pub extend DepCommand with Eq::{not_equal, equal}

///|
pub extend DepCommand with Debug::{to_repr}

///|
enum DepResponse {
  DepUnit
  DepMade(@qsm.Var)
} derive(Eq, Debug)

///|
pub extend DepResponse with Eq::{not_equal, equal}

///|
pub extend DepResponse with Debug::{to_repr}

///|
struct DepModel {
  step : Int32
  handles : Array[@qsm.Var]
} derive(Eq, Debug)

///|
pub extend DepModel with Eq::{not_equal, equal}

///|
pub extend DepModel with Debug::{to_repr}

///|
fn dep_config() -> @qsm.RunConfig {
  {
    seed: 17,
    cases: 1,
    max_commands: 6,
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
fn dep_contains(vars : Array[@qsm.Var], variable : @qsm.Var) -> Bool {
  for item in vars {
    if item == variable {
      return true
    }
  }
  false
}

///|
fn dep_spec() -> AsyncStateMachine[
  DepModel,
  Unit,
  DepCommand,
  DepCommand,
  DepResponse,
  DepResponse,
  Unit,
  Unit,
] {
  AsyncStateMachine::new(
    init_symbolic_model=() => { step: 0, handles: [], },
    init_concrete_model=() => (),
    init_system=() => (),
    generator=(model, _, _) => {
      match model.step {
        0 | 1 | 2 => Some(DepPad)
        3 => Some(DepMake)
        4 =>
          if model.handles.length() == 0 {
            None
          } else {
            Some(DepUse(model.handles[model.handles.length() - 1]))
          }
        5 => Some(DepPad)
        _ => None
      }
    },
    mock=(_, command, gen_sym) => {
      match command {
        DepMake => {
          let (fresh_var, next_gen_sym) = gen_sym.fresh()
          (DepMade(fresh_var), next_gen_sym)
        }
        DepPad | DepUse(_) => (DepUnit, gen_sym)
      }
    },
    transition_symbolic=(model, _, response) => {
      let handles = model.handles.copy()
      match response {
        DepMade(variable) => handles.push(variable)
        DepUnit => ()
      }
      { step: model.step + 1, handles, }
    },
    transition_concrete=(model, _, _) => model,
    precondition=(model, command) => {
      let ok = match command {
        DepUse(variable) => dep_contains(model.handles, variable)
        DepPad | DepMake => true
      }
      @qsm.Logic::boolean(ok)
    },
    response_vars=response => {
      match response {
        DepMade(variable) => [variable]
        DepUnit => []
      }
    },
    remap_command=(command, scope) => {
      match command {
        DepUse(variable) =>
          match scope.get(variable) {
            Some(mapped) => Some(DepUse(mapped))
            None => None
          }
        DepPad => Some(DepPad)
        DepMake => Some(DepMake)
      }
    },
    reify_command=(command, environment) => {
      match command {
        DepUse(variable) =>
          match environment.lookup(variable) {
            Ok(_) => Ok(command)
            Err(error) => Err(error)
          }
        DepPad | DepMake => Ok(command)
      }
    },
    run_command=(_, _) => DepUnit,
    bind_response=(symbolic, _, environment) => {
      match symbolic {
        DepMade(variable) => Ok(environment.insert(variable, ()))
        DepUnit => Ok(environment)
      }
    },
  )
}

///|
fn dep_branch_has_use(
  commands : @qsm.Commands[DepCommand, DepResponse],
) -> Bool {
  for command in commands.commands {
    if command.command is DepUse(_) {
      return true
    }
  }
  false
}

///|
test "async generation excludes commands depending on same chunk fresh vars" {
  match generate_parallel_commands_async_spec(dep_spec(), config=dep_config()) {
    Err(_) => fail("expected generated parallel commands")
    Ok(commands) => {
      let operation_count = commands.left.length() + commands.right.length()
      assert_eq(commands.prefix.length(), 3)
      assert_eq(operation_count, 1)
      assert_true(!dep_branch_has_use(commands.left))
      assert_true(!dep_branch_has_use(commands.right))
    }
  }
}

///|
enum IsoCommand {
  IsoMake
  IsoUse(@qsm.Var)
} derive(Eq, Debug)

///|
pub extend IsoCommand with Eq::{not_equal, equal}

///|
pub extend IsoCommand with Debug::{to_repr}

///|
enum IsoResponse {
  IsoMade(@qsm.Var)
  IsoUnit
} derive(Eq, Debug)

///|
pub extend IsoResponse with Eq::{not_equal, equal}

///|
pub extend IsoResponse with Debug::{to_repr}

///|
fn iso_spec() -> AsyncStateMachine[
  Unit,
  Unit,
  IsoCommand,
  IsoCommand,
  IsoResponse,
  IsoResponse,
  Unit,
  Unit,
] {
  AsyncStateMachine::new(
    init_symbolic_model=() => (),
    init_concrete_model=() => (),
    init_system=() => (),
    generator=(_, _, _) => None,
    mock=(_, _, gen_sym) => (IsoUnit, gen_sym),
    transition_symbolic=(_, _, _) => (),
    transition_concrete=(_, _, _) => (),
    reify_command=(command, environment) => {
      match command {
        IsoUse(variable) =>
          match environment.lookup(variable) {
            Ok(_) => Ok(command)
            Err(error) => Err(error)
          }
        IsoMake => Ok(command)
      }
    },
    run_command=(command, _) => {
      match command {
        IsoMake => IsoMade(@qsm.Var::{ id: 0, })
        IsoUse(_) => IsoUnit
      }
    },
    bind_response=(symbolic, _, environment) => {
      match symbolic {
        IsoMade(variable) => Ok(environment.insert(variable, ()))
        IsoUnit => Ok(environment)
      }
    },
  )
}

///|
fn iso_commands(
  command : IsoCommand,
  response : IsoResponse,
  vars : Array[@qsm.Var],
) -> @qsm.Commands[IsoCommand, IsoResponse] {
  @qsm.Commands::{ commands: [@qsm.Command::{ command, response, vars, }], }
}

///|
async test "branch environments are isolated until merge" {
  let variable = @qsm.Var::{ id: 0, }
  let base : @qsm.Environment[Unit] = @qsm.Environment::empty()
  let left_events : Array[@qsm.HistoryEvent[IsoCommand, IsoResponse]] = []
  let right_events : Array[@qsm.HistoryEvent[IsoCommand, IsoResponse]] = []
  let left = iso_commands(IsoMake, IsoMade(variable), [variable])
  let right = iso_commands(IsoUse(variable), IsoUnit, [])
  match run_branch_async(iso_spec(), left, base, (), 0, left_events) {
    Err(_) => fail("expected left branch to bind a variable")
    Ok(left_environment) => {
      assert_true(left_environment.contains(variable))
      assert_true(!base.contains(variable))
      match run_branch_async(iso_spec(), right, base, (), 1, right_events) {
        Err(BranchReifyFailed(error~, ..)) =>
          assert_true(error is @qsm.MissingVar(_))
        _ => fail("expected right branch reify failure against base env")
      }
    }
  }
}
