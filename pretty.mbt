///|
/// Formats a symbolic command program for display in a counterexample.
///
/// This deliberately prints the symbolic command and its mocked symbolic
/// response, because that is the stable program users can save and replay.
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
/// Formats the concrete execution history collected while replaying commands.
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
/// Formats predicate diagnostics, one message per line.
pub fn format_counterexample(counterexample : Counterexample) -> String {
  counterexample.messages.join("\n")
}

///|
/// Default failure formatter.
///
/// The failure type already stores the generated program, concrete history,
/// model state, and shrink statistics. This helper keeps formatting simple and
/// lets callers replace it with domain-specific pretty printing later.
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
/// Encodes a command program with a caller-provided serializer.
///
/// The library does not prescribe a wire format because user command and
/// response types are application-specific.
pub fn[CSym, RSym] save_commands(
  commands : Commands[CSym, RSym],
  encode : (Commands[CSym, RSym]) -> String,
) -> String {
  encode(commands)
}

///|
/// Decodes a command program with a caller-provided parser.
pub fn[CSym, RSym] load_commands(
  input : String,
  decode : (String) -> Result[Commands[CSym, RSym], String],
) -> Result[Commands[CSym, RSym], String] {
  decode(input)
}

///|
/// Decodes and replays a saved symbolic command program.
///
/// This is the MoonBit equivalent of rerunning a minimized QSM counterexample:
/// generation is skipped, but reification, execution, postconditions, binding,
/// invariants, labels, and cleanup still run normally.
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
