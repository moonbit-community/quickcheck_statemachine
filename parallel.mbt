///|
pub(all) struct ParallelCommands[CSym, RSym] {
  prefix : Commands[CSym, RSym]
  left : Commands[CSym, RSym]
  right : Commands[CSym, RSym]
} derive(Eq, Debug)

///|
pub(all) struct NParallelCommands[CSym, RSym] {
  prefix : Commands[CSym, RSym]
  suffixes : Array[Commands[CSym, RSym]]
} derive(Eq, Debug)

///|
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
