///|
/// Number of successful shrink steps and rounds used to minimize a failure.
pub(all) struct ShrinkStats {
  shrinks : Int
  rounds : Int
} derive(Eq, Debug)

///|
// Shrinking may rebuild a response, but it must keep the same number of freshly
// produced variables. Otherwise later commands could refer to a different
// dependency graph than the original program.
fn vars_match(old_vars : Array[Var], new_vars : Array[Var]) -> Bool {
  old_vars.length() == new_vars.length()
}

///|
// Extends the old-to-new symbolic variable map after a rebuilt command has
// produced its mock response. Later commands use this map to rewrite references
// to the variables that survived shrinking.
fn extend_scope(
  scope : Map[Var, Var],
  old_vars : Array[Var],
  new_vars : Array[Var],
) -> Map[Var, Var] {
  let next = scope.copy()
  for index in 0..<old_vars.length() {
    next[old_vars[index]] = new_vars[index]
  }
  next
}

///|
/// Rebuilds a candidate program and rejects it if symbolic dependencies break.
///
/// This is the dependency-aware part of shrinking. Removing or replacing a
/// command can invalidate later references. Instead of trusting the edited
/// program, we replay generation over the symbolic model:
///
/// * remap each command through the current old-to-new variable scope;
/// * re-check the precondition against the rebuilt symbolic model;
/// * regenerate the mock response and fresh variables deterministically;
/// * advance the symbolic model with `transition_symbolic`.
///
/// If any step fails, the candidate is discarded. If all steps succeed, the
/// returned program has a consistent symbolic environment and can be executed.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] shrink_and_validate(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
) -> Commands[CSym, RSym]? {
  let rebuilt : Array[Command[CSym, RSym]] = []
  for index = 0, model = (spec.init_symbolic_model)(), gen_sym = GenSym::new(), scope = Map([],
        ); index < commands.commands.length(); {
    let old = commands.commands[index]
    // `remap_command` is supplied by the user because only the user's command
    // type knows where symbolic references occur.
    match (spec.remap_command)(old.command, scope) {
      None => break None
      Some(new_command) => {
        let precondition = (spec.precondition)(model, new_command)
        if !precondition.eval() {
          break None
        }
        let (new_response, next_gen_sym) = (spec.mock)(
          model, new_command, gen_sym,
        )
        let new_vars = (spec.response_vars)(new_response)
        // A command that used to introduce `n` variables must still introduce
        // `n` variables after rebuilding so references can be mapped positionally.
        if !vars_match(old.vars, new_vars) {
          break None
        }
        let command = Command::{
          command: new_command,
          response: new_response,
          vars: new_vars,
        }
        rebuilt.push(command)
        let next_scope = extend_scope(scope, old.vars, new_vars)
        let next_model = (spec.transition_symbolic)(
          model,
          command.command,
          command.response,
        )
        continue index + 1, next_model, next_gen_sym, next_scope
      }
    }
  } nobreak {
    Some({ commands: rebuilt })
  }
}

///|
// Builds the "delete one command" candidate used by the first shrink pass.
fn[CSym, RSym] without_index(
  commands : Commands[CSym, RSym],
  index : Int,
) -> Commands[CSym, RSym] {
  let next : Array[Command[CSym, RSym]] = []
  for i, command in commands.commands {
    if i != index {
      next.push(command)
    }
  }
  { commands: next }
}

///|
// Builds the "replace one command by a smaller command" candidate used by the
// second shrink pass.
fn[CSym, RSym] replace_index(
  commands : Commands[CSym, RSym],
  index : Int,
  command : Command[CSym, RSym],
) -> Commands[CSym, RSym] {
  let next = commands.commands.copy()
  next[index] = command
  { commands: next }
}

///|
/// Produces one round of smaller, dependency-valid command programs.
///
/// The candidates are generated in two phases: first try deleting each command,
/// then try command-specific replacements supplied by `shrinker`. Every edited
/// program is sent through `shrink_and_validate` before it is returned, so later
/// replay does not waste time on candidates with dangling symbolic variables.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] shrink_commands_once(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
) -> Array[Commands[CSym, RSym]] {
  let candidates : Array[Commands[CSym, RSym]] = []
  for index in 0..<commands.commands.length() {
    match shrink_and_validate(spec, without_index(commands, index)) {
      Some(candidate) => candidates.push(candidate)
      None => ()
    }
  }
  for index = 0, model = (spec.init_symbolic_model)(), gen_sym = GenSym::new(); index <
     commands.commands.length(); {
    let old = commands.commands[index]
    // The user shrinker sees the symbolic model at the original command
    // position, just as generation did. This lets domain shrinkers preserve
    // precondition-sensitive choices.
    for smaller in (spec.shrinker)(model, old.command) {
      let (new_response, _) = (spec.mock)(model, smaller, gen_sym)
      let new_vars = (spec.response_vars)(new_response)
      if vars_match(old.vars, new_vars) {
        let replacement = Command::{
          command: smaller,
          response: new_response,
          vars: new_vars,
        }
        match
          shrink_and_validate(spec, replace_index(commands, index, replacement)) {
          Some(candidate) => candidates.push(candidate)
          None => ()
        }
      }
    }
    let (_, next_gen_sym) = (spec.mock)(model, old.command, gen_sym)
    let next_model = (spec.transition_symbolic)(
      model,
      old.command,
      old.response,
    )
    continue index + 1, next_model, next_gen_sym
  } nobreak {
    candidates
  }
}

///|
/// Returns the first candidate that still reproduces the failure.
///
/// This keeps the shrinking loop simple and deterministic: each round accepts
/// one smaller failing program, then restarts from that program.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] first_failing_candidate(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  candidates : Array[Commands[CSym, RSym]],
  config : RunConfig,
) -> Commands[CSym, RSym]? {
  for candidate in candidates {
    match run_commands(spec, candidate, config~) {
      Err(_) => return Some(candidate)
      Ok(_) => ()
    }
  }
  None
}
