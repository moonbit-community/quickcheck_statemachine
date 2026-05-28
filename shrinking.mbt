///|
pub(all) struct ShrinkStats {
  shrinks : Int
  rounds : Int
} derive(Eq, Debug)

///|
fn vars_match(old_vars : Array[Var], new_vars : Array[Var]) -> Bool {
  old_vars.length() == new_vars.length()
}

///|
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
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] shrink_and_validate(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
) -> Commands[CSym, RSym]? {
  let rebuilt : Array[Command[CSym, RSym]] = []
  for index = 0, model = (spec.init_symbolic_model)(), gen_sym = GenSym::new(), scope = Map([],
        ); index < commands.commands.length(); {
    let old = commands.commands[index]
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
