///|
/// Model transition event passed to coverage labelers.
///
/// The standalone `Labeler` helper receives both the model before the command
/// and the model after the transition. The `StateMachine.label` callback used by
/// replay is lighter weight: it receives the concrete model before the command,
/// the concrete command, and the concrete response.
pub(all) struct Event[Model, Command, Response] {
  before_model : Model
  command : Command
  response : Response
  after_model : Model
} derive(Eq, Debug)

///|
/// Callback wrapper for classifying a state-machine event.
pub(all) struct Labeler[Model, Command, Response] {
  classify : (Event[Model, Command, Response]) -> Array[String]
}

///|
/// Applies a labeler to one event.
pub fn[Model, Command, Response] classify(
  labeler : Labeler[Model, Command, Response],
  event : Event[Model, Command, Response],
) -> Array[String] {
  (labeler.classify)(event)
}

///|
// Small local helper used by label and command-name coverage checks.
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
/// Deduplicates labels while preserving first-seen order.
///
/// The report only needs to show whether a scenario occurred at least once, but
/// preserving order keeps the output stable for tests and saved diagnostics.
pub fn collect_labels(labels : Array[String]) -> Array[String] {
  let unique : Array[String] = []
  for label in labels {
    if !contains_string(unique, label) {
      unique.push(label)
    }
  }
  unique
}

///|
/// Counts how often each command name appears in a generated program.
///
/// `command_name` coverage is a coarse audit that generation is exploring every
/// operation family expected by the test.
pub fn[CSym, RSym] command_names(
  commands : Commands[CSym, RSym],
  name : (CSym) -> String,
) -> Array[(String, Int)] {
  let counts : Map[String, Int] = Map([])
  for command in commands.commands {
    let command_name = name(command.command)
    counts[command_name] = counts.get_or_default(command_name, 0) + 1
  }
  counts.to_array()
}

///|
/// Lists command names in first-seen order without counts.
pub fn[CSym, RSym] command_names_in_order(
  commands : Commands[CSym, RSym],
  name : (CSym) -> String,
) -> Array[String] {
  let names : Array[String] = []
  for command in commands.commands {
    let command_name = name(command.command)
    if !contains_string(names, command_name) {
      names.push(command_name)
    }
  }
  names
}

///|
/// Returns the required command names that did not appear in a run.
pub fn cover_command_names(
  seen : Array[(String, Int)],
  required : Array[String],
) -> Array[String] {
  let missing : Array[String] = []
  for name in required {
    let present = for item in seen {
      if item.0 == name && item.1 > 0 {
        break true
      }
    } nobreak {
      false
    }
    if !present {
      missing.push(name)
    }
  }
  missing
}
