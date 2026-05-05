///|
pub(all) struct Counterexample {
  messages : Array[String]
} derive(Eq, Debug)

///|
pub(all) enum LogicValue {
  Holds
  Fails(Counterexample)
} derive(Eq, Debug)

///|
pub(all) enum Logic {
  Top
  Bot
  Boolean(Bool)
  Predicate(name~ : String, value~ : Bool)
  And(Logic, Logic)
  Or(Logic, Logic)
  Implies(Logic, Logic)
  Not(Logic)
  Annotate(message~ : String, logic~ : Logic)
} derive(Eq, Debug)

///|
pub fn Logic::top() -> Logic {
  Top
}

///|
pub fn Logic::bot() -> Logic {
  Bot
}

///|
pub fn Logic::boolean(value : Bool) -> Logic {
  Boolean(value)
}

///|
pub fn Logic::predicate(name~ : String, value~ : Bool) -> Logic {
  Predicate(name~, value~)
}

///|
pub fn Logic::annotate(self : Logic, message : String) -> Logic {
  Annotate(message~, logic=self)
}

///|
pub fn Logic::eval(self : Logic) -> Bool {
  match self {
    Top => true
    Bot => false
    Boolean(value) => value
    Predicate(value~, ..) => value
    And(left, right) => left.eval() && right.eval()
    Or(left, right) => left.eval() || right.eval()
    Implies(left, right) => !left.eval() || right.eval()
    Not(logic) => !logic.eval()
    Annotate(logic~, ..) => logic.eval()
  }
}

///|
fn merge_messages(left : Array[String], right : Array[String]) -> Array[String] {
  let messages = left.copy()
  for message in right {
    messages.push(message)
  }
  messages
}

///|
fn logic_failure_messages(logic : Logic) -> Array[String] {
  match logic {
    Top => []
    Bot => ["logic is false"]
    Boolean(value) => if value { [] } else { ["boolean predicate is false"] }
    Predicate(name~, value~) => if value { [] } else { [name] }
    And(left, right) => {
      let left_messages = logic_failure_messages(left)
      let right_messages = logic_failure_messages(right)
      merge_messages(left_messages, right_messages)
    }
    Or(left, right) =>
      if left.eval() || right.eval() {
        []
      } else {
        merge_messages(
          logic_failure_messages(left),
          logic_failure_messages(right),
        )
      }
    Implies(left, right) =>
      if !left.eval() || right.eval() {
        []
      } else {
        merge_messages(
          ["implication consequent is false"],
          logic_failure_messages(right),
        )
      }
    Not(logic) => if logic.eval() { ["negated predicate is true"] } else { [] }
    Annotate(message~, logic~) =>
      if logic.eval() {
        []
      } else {
        let messages = [message]
        for child in logic_failure_messages(logic) {
          messages.push(child)
        }
        messages
      }
  }
}

///|
pub fn Logic::counterexample(self : Logic) -> Counterexample {
  Counterexample::{ messages: logic_failure_messages(self) }
}

///|
pub fn Logic::check(self : Logic) -> LogicValue {
  if self.eval() {
    Holds
  } else {
    Fails(self.counterexample())
  }
}

///|
pub fn logic_and(left : Logic, right : Logic) -> Logic {
  And(left, right)
}

///|
pub fn logic_or(left : Logic, right : Logic) -> Logic {
  Or(left, right)
}

///|
pub fn logic_implies(left : Logic, right : Logic) -> Logic {
  Implies(left, right)
}

///|
pub fn logic_not(logic : Logic) -> Logic {
  Not(logic)
}
