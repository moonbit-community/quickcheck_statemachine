///|
/// Async variant of `StateMachine`.
///
/// Pure model, generation, reference, shrink, naming, and labelling callbacks keep
/// the same shape as the synchronous state machine. Only callbacks that touch the
/// implementation under test are async.
pub struct AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
  init_symbolic_model : () -> MSym
  init_concrete_model : () -> MCon
  init_system : async () -> S
  generator : (MSym, Int32, @splitmix.RandomState) -> CSym?
  mock : (MSym, CSym, @qsm.GenSym) -> (RSym, @qsm.GenSym)
  response_vars : (RSym) -> Array[@qsm.Var]
  transition_symbolic : (MSym, CSym, RSym) -> MSym
  transition_concrete : (MCon, CCon, RCon) -> MCon
  precondition : (MSym, CSym) -> @qsm.Logic
  postcondition : (MCon, CCon, RCon) -> @qsm.Logic
  invariant : (MCon) -> @qsm.Logic
  shrinker : (MSym, CSym) -> Array[CSym]
  remap_command : (CSym, Map[@qsm.Var, @qsm.Var]) -> CSym?
  reify_command : (CSym, @qsm.Environment[V]) -> Result[CCon, @qsm.EnvError]
  run_command : async (CCon, S) -> RCon
  bind_response : (RSym, RCon, @qsm.Environment[V]) -> Result[
    @qsm.Environment[V],
    @qsm.BindError,
  ]
  cleanup : async (MCon, S) -> Unit
  command_name : (CSym) -> String
  label : (MCon, CCon, RCon) -> Array[String]
}

///|
/// Builds an async state machine with the same optional defaults as
/// `StateMachine::new`.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] AsyncStateMachine::new(
  init_symbolic_model~ : () -> MSym,
  init_concrete_model~ : () -> MCon,
  init_system~ : async () -> S,
  generator~ : (MSym, Int32, @splitmix.RandomState) -> CSym?,
  mock~ : (MSym, CSym, @qsm.GenSym) -> (RSym, @qsm.GenSym),
  transition_symbolic~ : (MSym, CSym, RSym) -> MSym,
  transition_concrete~ : (MCon, CCon, RCon) -> MCon,
  reify_command~ : (CSym, @qsm.Environment[V]) -> Result[CCon, @qsm.EnvError],
  run_command~ : async (CCon, S) -> RCon,
  bind_response~ : (RSym, RCon, @qsm.Environment[V]) -> Result[
    @qsm.Environment[V],
    @qsm.BindError,
  ],
  postcondition~ : (MCon, CCon, RCon) -> @qsm.Logic = (_, _, _) => {
    @qsm.Logic::top()
  },
  precondition~ : (MSym, CSym) -> @qsm.Logic = (_, _) => @qsm.Logic::top(),
  invariant~ : (MCon) -> @qsm.Logic = _ => @qsm.Logic::top(),
  response_vars~ : (RSym) -> Array[@qsm.Var] = _ => [],
  shrinker~ : (MSym, CSym) -> Array[CSym] = (_, _) => [],
  remap_command~ : (CSym, Map[@qsm.Var, @qsm.Var]) -> CSym? = (command, _) => {
    Some(command)
  },
  cleanup~ : async (MCon, S) -> Unit = (_, _) => (),
  command_name~ : (CSym) -> String = _ => "command",
  label~ : (MCon, CCon, RCon) -> Array[String] = (_, _, _) => [],
) -> AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
  {
    init_symbolic_model,
    init_concrete_model,
    init_system,
    generator,
    mock,
    response_vars,
    transition_symbolic,
    transition_concrete,
    precondition,
    postcondition,
    invariant,
    shrinker,
    remap_command,
    reify_command,
    run_command,
    bind_response,
    cleanup,
    command_name,
    label,
  }
}

///|
/// Lifts a synchronous state machine into the async API.
///
/// Without suspension points in `run_command`, branch commands still execute
/// atomically under MoonBit's cooperative async runtime.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] AsyncStateMachine::from_sync(
  spec : @qsm.StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
) -> AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
  AsyncStateMachine::new(
    init_symbolic_model=spec.init_symbolic_model,
    init_concrete_model=spec.init_concrete_model,
    init_system=() => (spec.init_system)(),
    generator=spec.generator,
    mock=spec.mock,
    transition_symbolic=spec.transition_symbolic,
    transition_concrete=spec.transition_concrete,
    reify_command=spec.reify_command,
    run_command=(command, system) => (spec.run_command)(command, system),
    bind_response=spec.bind_response,
    postcondition=spec.postcondition,
    precondition=spec.precondition,
    invariant=spec.invariant,
    response_vars=spec.response_vars,
    shrinker=spec.shrinker,
    remap_command=spec.remap_command,
    cleanup=(model, system) => (spec.cleanup)(model, system),
    command_name=spec.command_name,
    label=spec.label,
  )
}
