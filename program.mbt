///|
/// One generated symbolic command, its symbolic response, and fresh variables.
///
/// `command` is the action the generator chose. `response` is the mocked
/// symbolic response used to advance the symbolic model before the real system
/// has run. `vars` records which variables were introduced by that response so
/// shrink validation can remap dependencies later.
pub(all) struct Command[CSym, RSym] {
  command : CSym
  response : RSym
  vars : Array[Var]
} derive(Eq, Debug)

///|
/// A symbolic command program.
///
/// This is the stable artifact that can be shrunk, formatted, saved, loaded,
/// and replayed. It intentionally stores symbolic responses, not concrete
/// responses, because those are what make the program self-contained before
/// execution.
pub(all) struct Commands[CSym, RSym] {
  commands : Array[Command[CSym, RSym]]
} derive(Eq, Debug)

///|
/// Constructs an empty command program.
pub fn[CSym, RSym] Commands::empty() -> Commands[CSym, RSym] {
  { commands: [] }
}

///|
/// Returns the number of generated commands.
pub fn[CSym, RSym] Commands::length(self : Commands[CSym, RSym]) -> Int {
  self.commands.length()
}

///|
/// Appends one command while preserving the original program.
pub fn[CSym, RSym] Commands::append(
  self : Commands[CSym, RSym],
  command : Command[CSym, RSym],
) -> Commands[CSym, RSym] {
  let commands = self.commands.copy()
  commands.push(command)
  { commands, }
}

///|
/// Concatenates two command programs.
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
/// Configuration shared by generation, execution, coverage checks, and
/// shrinking.
pub(all) struct RunConfig {
  // Base seed. `check` derives case seeds by adding the case index.
  seed : UInt64
  // Number of independent generated programs to test.
  cases : Int
  // Maximum length of each generated command program.
  max_commands : Int
  // Size hint passed to the user generator.
  size : Int
  // Number of times generation may retry after a precondition rejects a command.
  max_tries : Int
  // Whether `check` should minimize a failing generated program.
  shrink : Bool
  // Maximum number of accepted shrink steps.
  max_shrinks : Int
  // Maximum number of shrink rounds. Each round starts from the current best
  // failing program and searches for one smaller failing candidate.
  max_shrink_rounds : Int
  // Semantic coverage labels that must appear in a successful run.
  required_labels : Array[String]
  // Command families that must appear in a successful run.
  required_command_names : Array[String]
} derive(Eq, Debug)

///|
/// Conservative defaults suitable for examples and small model tests.
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
/// `Default` implementation forwarding to `RunConfig::default`.
pub impl Default for RunConfig with fn default() {
  RunConfig::default()
}

///|
/// Failures that can occur while generating a symbolic command program.
pub(all) enum GenerationFailure[MSym, CSym, RSym] {
  // The `RunConfig` cannot be used, for example because a limit is negative.
  InvalidGenerationConfig(String)
  // The generator kept producing commands rejected by the precondition. This
  // usually means the model has reached a terminal state that should return
  // `None`, or the generator is not respecting the current model.
  Deadlock(
    step_index~ : Int,
    model~ : MSym,
    commands~ : Commands[CSym, RSym],
    last_precondition~ : Logic?
  )
} derive(Eq, Debug)

///|
/// Complete state-machine specification.
///
/// This record is the MoonBit counterpart of QSM's `StateMachine`: users supply
/// the pure model operations, symbolic/reference plumbing, and real semantics;
/// the library supplies generation, replay, shrinking, and reporting.
///
/// The type separates symbolic and concrete model/command/response types:
/// symbolic callbacks run before the system exists, while concrete callbacks run
/// against the implementation under test.
pub struct StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S] {
  // Initial model used by generation and shrinking.
  init_symbolic_model : () -> MSym
  // Initial model used by replay against the concrete system.
  init_concrete_model : () -> MCon
  // Creates the mutable system under test for one replay.
  init_system : () -> S raise
  // Proposes the next symbolic command from the current symbolic model.
  // Returning `None` stops generation cleanly.
  generator : (MSym, Int, @splitmix.RandomState) -> CSym?
  // Predicts the symbolic response so generation can advance the model before
  // execution. This is where commands that create resources allocate `Var`s.
  mock : (MSym, CSym, GenSym) -> (RSym, GenSym)
  // Extracts variables introduced by a symbolic response, in positional order.
  response_vars : (RSym) -> Array[Var]
  // Advances the symbolic model during generation and shrink validation.
  transition_symbolic : (MSym, CSym, RSym) -> MSym
  // Advances the concrete model after executing a concrete command.
  transition_concrete : (MCon, CCon, RCon) -> MCon
  // Rejects commands that are not valid in the current symbolic model.
  precondition : (MSym, CSym) -> Logic
  // Checks the observed concrete response against the model.
  postcondition : (MCon, CCon, RCon) -> Logic
  // Checks model-wide properties after each transition.
  invariant : (MCon) -> Logic
  // Produces smaller versions of one symbolic command.
  shrinker : (MSym, CSym) -> Array[CSym]
  // Rewrites symbolic variables after earlier commands have been deleted or
  // rebuilt during shrinking.
  remap_command : (CSym, Map[Var, Var]) -> CSym?
  // Turns symbolic references into concrete values using the environment.
  reify_command : (CSym, Environment[V]) -> Result[CCon, EnvError]
  // Executes the concrete command against the mutable system under test.
  run_command : (CCon, S) -> RCon raise
  // Binds concrete values returned by the real response to variables predicted
  // by the symbolic response.
  bind_response : (RSym, RCon, Environment[V]) -> Result[
    Environment[V],
    BindError,
  ]
  // Releases resources after a replay, successful or not.
  cleanup : (MCon, S) -> Unit raise
  // Human-readable command family name used for coverage reports.
  command_name : (CSym) -> String
  // Semantic labels collected from concrete execution for coverage reports.
  label : (MCon, CCon, RCon) -> Array[String]
}

///|
/// Builds a `StateMachine` with conservative defaults for optional callbacks.
///
/// Required callbacks describe the core state-machine loop: initialize models
/// and system, generate symbolic commands, mock responses, transition models,
/// reify commands, run the system, and bind newly produced concrete values.
/// Optional callbacks default to permissive behavior so small examples can
/// start with only the essential pieces.
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
// Validates limits before generation or replay starts. Replay uses the same
// config because coverage checks and shrinking limits are part of the run too.
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
// Internal result of asking the generator for one valid symbolic command.
priv enum Selection[CSym] {
  // The generator explicitly stopped this program.
  Stop
  // A command satisfied the precondition.
  Selected(CSym)
  // The retry budget was exhausted by rejected commands. The final
  // precondition is retained for diagnostics.
  Exhausted(Logic?)
}

///|
// Calls the user generator until it either stops, produces a command accepted by
// the precondition, or exhausts `max_tries`.
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
/// Generates one symbolic command program using an explicit seed.
///
/// Generation follows the QSM symbolic loop: select a precondition-valid
/// command, ask `mock` for the symbolic response, record response variables,
/// advance the symbolic model, and repeat until `max_commands` or generator
/// termination.
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
            // The mocked response is part of the generated program. It gives
            // later symbolic commands stable variables to mention and keeps the
            // symbolic model in lockstep with the command prefix.
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
/// Generates one symbolic command program using `config.seed`.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
) -> Result[Commands[CSym, RSym], GenerationFailure[MSym, CSym, RSym]] {
  generate_commands_with_seed(spec, config~)
}
