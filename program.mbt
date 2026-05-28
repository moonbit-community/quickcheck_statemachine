///|
pub(all) struct Command[CSym, RSym] {
  command : CSym
  response : RSym
  vars : Array[Var]
} derive(Eq, Debug)

///|
pub(all) struct Commands[CSym, RSym] {
  commands : Array[Command[CSym, RSym]]
} derive(Eq, Debug)

///|
pub fn[CSym, RSym] Commands::empty() -> Commands[CSym, RSym] {
  { commands: [] }
}

///|
pub fn[CSym, RSym] Commands::length(self : Commands[CSym, RSym]) -> Int {
  self.commands.length()
}

///|
pub fn[CSym, RSym] Commands::append(
  self : Commands[CSym, RSym],
  command : Command[CSym, RSym],
) -> Commands[CSym, RSym] {
  let commands = self.commands.copy()
  commands.push(command)
  { commands, }
}

///|
pub fn[CSym, RSym] Commands::concat(
  left : Commands[CSym, RSym],
  right : Commands[CSym, RSym],
) -> Commands[CSym, RSym] {
  let commands = left.commands.copy()
  for command in right.commands {
    commands.push(command)
  }
  { commands, }
}

///|
pub(all) struct RunConfig {
  seed : UInt64
  cases : Int
  max_commands : Int
  size : Int
  max_tries : Int
  shrink : Bool
  max_shrinks : Int
  max_shrink_rounds : Int
  required_labels : Array[String]
  required_command_names : Array[String]
} derive(Eq, Debug)

///|
pub fn RunConfig::default() -> RunConfig {
  {
    seed: 37,
    cases: 100,
    max_commands: 50,
    size: 100,
    max_tries: 100,
    shrink: true,
    max_shrinks: 100,
    max_shrink_rounds: 20,
    required_labels: [],
    required_command_names: [],
  }
}

///|
pub impl Default for RunConfig with fn default() {
  RunConfig::default()
}

///|
pub(all) enum GenerationFailure[MSym, CSym, RSym] {
  InvalidGenerationConfig(String)
  Deadlock(
    step_index~ : Int,
    model~ : MSym,
    commands~ : Commands[CSym, RSym],
    last_precondition~ : Logic?
  )
} derive(Eq, Debug)

///|
pub struct StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
  init_symbolic_model : () -> MSym
  init_concrete_model : () -> MCon
  init_system : () -> S raise
  generator : (MSym, Int, @splitmix.RandomState) -> CSym?
  mock : (MSym, CSym, GenSym) -> (RSym, GenSym)
  response_vars : (RSym) -> Array[Var]
  transition_symbolic : (MSym, CSym, RSym) -> MSym
  transition_concrete : (MCon, CCon, RCon) -> MCon
  precondition : (MSym, CSym) -> Logic
  postcondition : (MCon, CCon, RCon) -> Logic
  invariant : (MCon) -> Logic
  shrinker : (MSym, CSym) -> Array[CSym]
  remap_command : (CSym, Map[Var, Var]) -> CSym?
  reify_command : (CSym, Environment[V]) -> Result[CCon, EnvError]
  run_command : (CCon, S) -> RCon raise
  bind_response : (RSym, RCon, Environment[V]) -> Result[
    Environment[V],
    BindError,
  ]
  cleanup : (MCon, S) -> Unit raise
  command_name : (CSym) -> String
  label : (MCon, CCon, RCon) -> Array[String]
}

///|
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] StateMachine::new(
  init_symbolic_model~ : () -> MSym,
  init_concrete_model~ : () -> MCon,
  init_system~ : () -> S raise,
  generator~ : (MSym, Int, @splitmix.RandomState) -> CSym?,
  mock~ : (MSym, CSym, GenSym) -> (RSym, GenSym),
  transition_symbolic~ : (MSym, CSym, RSym) -> MSym,
  transition_concrete~ : (MCon, CCon, RCon) -> MCon,
  reify_command~ : (CSym, Environment[V]) -> Result[CCon, EnvError],
  run_command~ : (CCon, S) -> RCon raise,
  bind_response~ : (RSym, RCon, Environment[V]) -> Result[
    Environment[V],
    BindError,
  ],
  postcondition? : (MCon, CCon, RCon) -> Logic = (_, _, _) => Logic::top(),
  precondition? : (MSym, CSym) -> Logic = (_, _) => Logic::top(),
  invariant? : (MCon) -> Logic = _ => Logic::top(),
  response_vars? : (RSym) -> Array[Var] = _ => [],
  shrinker? : (MSym, CSym) -> Array[CSym] = (_, _) => [],
  remap_command? : (CSym, Map[Var, Var]) -> CSym? = (command, _) => {
    Some(command)
  },
  cleanup? : (MCon, S) -> Unit raise = (_, _) => (),
  command_name? : (CSym) -> String = _ => "command",
  label? : (MCon, CCon, RCon) -> Array[String] = (_, _, _) => [],
) -> StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
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
fn validate_generation_config(config : RunConfig) -> String? {
  if config.cases < 0 {
    Some("cases must be non-negative")
  } else if config.max_commands < 0 {
    Some("max_commands must be non-negative")
  } else if config.size < 0 {
    Some("size must be non-negative")
  } else if config.max_tries <= 0 {
    Some("max_tries must be positive")
  } else if config.max_shrinks < 0 {
    Some("max_shrinks must be non-negative")
  } else if config.max_shrink_rounds < 0 {
    Some("max_shrink_rounds must be non-negative")
  } else {
    None
  }
}

///|
priv enum Selection[CSym] {
  Stop
  Selected(CSym)
  Exhausted(Logic?)
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] select_symbolic_command(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  model : MSym,
  size : Int,
  rng : @splitmix.RandomState,
  max_tries : Int,
) -> Selection[CSym] {
  for tries = 0, last_precondition = None; tries < max_tries; {
    match (spec.generator)(model, size, rng) {
      None => break Stop
      Some(command) => {
        let precondition = (spec.precondition)(model, command)
        if precondition.eval() {
          break Selected(command)
        } else {
          continue tries + 1, Some(precondition)
        }
      }
    }
  } nobreak {
    Exhausted(last_precondition)
  }
}

///|
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_commands_with_seed(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
  seed? : UInt64 = config.seed,
) -> Result[Commands[CSym, RSym], GenerationFailure[MSym, CSym, RSym]] {
  match validate_generation_config(config) {
    Some(message) => Err(InvalidGenerationConfig(message))
    None => {
      let rng = @splitmix.new(seed~)
      let initial_commands : Commands[CSym, RSym] = Commands::empty()
      for step_index = 0, model = (spec.init_symbolic_model)(), gen_sym = GenSym::new(), commands = initial_commands; step_index <
         config.max_commands; {
        match
          select_symbolic_command(
            spec,
            model,
            config.size,
            rng,
            config.max_tries,
          ) {
          Stop => break Ok(commands)
          Exhausted(last_precondition) =>
            break Err(
              Deadlock(step_index~, model~, commands~, last_precondition~),
            )
          Selected(symbolic_command) => {
            let (symbolic_response, next_gen_sym) = (spec.mock)(
              model, symbolic_command, gen_sym,
            )
            let vars = (spec.response_vars)(symbolic_response)
            let command = Command::{
              command: symbolic_command,
              response: symbolic_response,
              vars,
            }
            let next_model = (spec.transition_symbolic)(
              model,
              command.command,
              command.response,
            )
            continue step_index + 1,
              next_model,
              next_gen_sym,
              commands.append(command)
          }
        }
      } nobreak {
        Ok(commands)
      }
    }
  }
}

///|
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
) -> Result[Commands[CSym, RSym], GenerationFailure[MSym, CSym, RSym]] {
  generate_commands_with_seed(spec, config~)
}
