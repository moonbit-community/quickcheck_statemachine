///|
pub fn[CSym : @debug.Debug, RSym : @debug.Debug] format_commands(
  commands : Commands[CSym, RSym],
) -> String {
  let builder = StringBuilder::new()
  for index, command in commands.commands {
    builder.write_string("\{index}: ")
    builder.write_string(@debug.to_string(command.command))
    builder.write_string(" -> ")
    builder.write_string(@debug.to_string(command.response))
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
pub fn[C : @debug.Debug, R : @debug.Debug] format_history(
  history : History[C, R],
) -> String {
  let builder = StringBuilder::new()
  for event in history.events {
    builder.write_string(@debug.to_string(event))
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
pub fn format_counterexample(counterexample : Counterexample) -> String {
  counterexample.messages.join("\n")
}

///|
pub fn[
  MSym : @debug.Debug,
  MCon : @debug.Debug,
  CSym : @debug.Debug,
  CCon : @debug.Debug,
  RSym : @debug.Debug,
  RCon : @debug.Debug,
] format_failure(
  failure : RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
) -> String {
  @debug.to_string(failure)
}

///|
pub fn[CSym, RSym] save_commands(
  commands : Commands[CSym, RSym],
  encode : (Commands[CSym, RSym]) -> String,
) -> String {
  encode(commands)
}

///|
pub fn[CSym, RSym] load_commands(
  input : String,
  decode : (String) -> Result[Commands[CSym, RSym], String],
) -> Result[Commands[CSym, RSym], String] {
  decode(input)
}

///|
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_saved_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  input : String,
  decode : (String) -> Result[Commands[CSym, RSym], String],
  config? : RunConfig = RunConfig::default(),
) -> Result[
  RunReport[CSym, RSym, CCon, RCon],
  RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match decode(input) {
    Err(message) => Err(InvalidConfig(message))
    Ok(commands) => replay(spec, commands, config~)
  }
}
