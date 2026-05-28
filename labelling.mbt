///|
pub(all) struct Event[Model, Command, Response] {
  before_model : Model
  command : Command
  response : Response
  after_model : Model
} derive(Eq, Debug)

///|
pub(all) struct Labeler[Model, Command, Response] {
  classify : (Event[Model, Command, Response]) -> Array[String]
}

///|
pub fn[Model, Command, Response] classify(
  labeler : Labeler[Model, Command, Response],
  event : Event[Model, Command, Response],
) -> Array[String] {
  (labeler.classify)(event)
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
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
