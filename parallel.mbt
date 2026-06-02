///|
/// A two-branch parallel command program.
///
/// The `prefix` is executed first to set up shared state. `left` and `right`
/// represent commands that should be considered concurrent. The current runner
/// linearizes them deterministically; the shape is kept explicit so a future
/// implementation can replace that with real concurrent execution and
/// linearizability search.
pub(all) struct ParallelCommands[CSym, RSym] {
  prefix : Commands[CSym, RSym]
  left : Commands[CSym, RSym]
  right : Commands[CSym, RSym]
} derive(Eq, Debug)

///|
/// Generalized representation for more than two parallel suffixes.
///
/// This mirrors the structure described by QSM: a sequential prefix followed by
/// one or more groups of commands whose operations may overlap.
pub(all) struct NParallelCommands[CSym, RSym] {
  prefix : Commands[CSym, RSym]
  suffixes : Array[Commands[CSym, RSym]]
} derive(Eq, Debug)

///|
// Copies a half-open slice of a generated symbolic program.
fn[CSym, RSym] take_commands(
  commands : Commands[CSym, RSym],
  start : Int,
  end : Int,
) -> Commands[CSym, RSym] {
  let taken : Array[Command[CSym, RSym]] = []
  for index in start..<end {
    taken.push(commands.commands[index])
  }
  { commands: taken }
}

///|
/// Generates a sequential program and splits it into prefix, left, and right.
///
/// QSM's parallel property generates commands from one symbolic model and then
/// runs a prefix before exploring concurrent suffixes. This helper preserves the
/// same command-program shape even though execution is currently reduced to a
/// deterministic linearization.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_parallel_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
) -> Result[ParallelCommands[CSym, RSym], GenerationFailure[MSym, CSym, RSym]] {
  match generate_commands(spec, config~) {
    Err(failure) => Err(failure)
    Ok(commands) => {
      let len = commands.length()
      let prefix_len = len / 2
      let suffix_len = len - prefix_len
      let left_len = suffix_len / 2
      Ok({
        prefix: take_commands(commands, 0, prefix_len),
        left: take_commands(commands, prefix_len, prefix_len + left_len),
        right: take_commands(commands, prefix_len + left_len, len),
      })
    }
  }
}

///|
/// Produces the sequential order currently used to replay a parallel program.
///
/// A complete linearizability checker would search all histories that respect
/// invocation/response ordering. Until that exists, this function makes the
/// chosen order explicit and testable.
pub fn[CSym, RSym] linearise(
  commands : ParallelCommands[CSym, RSym],
) -> Commands[CSym, RSym]? {
  Some(
    Commands::concat(
      Commands::concat(commands.prefix, commands.left),
      commands.right,
    ),
  )
}

///|
/// Runs a parallel-shaped program through the current linearization path.
///
/// This gives users a stable API for parallel properties while the internal
/// implementation remains conservative. Any future concurrent runner can keep
/// this entry point and strengthen the semantics behind it.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_parallel_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : ParallelCommands[CSym, RSym],
  config? : RunConfig = RunConfig::default(),
) -> Result[
  RunReport[CSym, RSym, CCon, RCon],
  RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match linearise(commands) {
    None => Err(InvalidConfig("parallel command program has no linearization"))
    Some(sequential) => run_commands(spec, sequential, config~)
  }
}
