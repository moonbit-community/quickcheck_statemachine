///|
/// Human-readable explanation collected from a failed logical condition.
///
/// Preconditions, postconditions, and invariants use `Logic` instead of plain
/// `Bool` so that a failing command can report which model predicate failed,
/// much like QSM's annotated counterexamples.
pub(all) struct Counterexample {
  messages : Array[String]
} derive(Eq, Debug)

///|
/// Result of evaluating a logical condition with diagnostics preserved.
pub(all) enum LogicValue {
  Holds
  Fails(Counterexample)
} derive(Eq, Debug)

///|
/// Boolean logic tree used by model predicates.
///
/// `Logic` is deliberately small: it can be evaluated as a Boolean, but it also
/// retains predicate names and annotations for counterexample formatting. Use it
/// for preconditions, postconditions, invariants, and any helper predicate whose
/// failure should remain visible after shrinking.
pub(all) enum Logic {
  // Always true.
  Top
  // Always false.
  Bot
  // A plain Boolean when no diagnostic name is needed.
  Boolean(Bool)
  // A named predicate; the name is emitted when `value` is false.
  Predicate(name~ : String, value~ : Bool)
  // Both operands must hold. Failure messages from both sides are preserved.
  And(Logic, Logic)
  // At least one operand must hold. If both fail, both explanations are kept.
  Or(Logic, Logic)
  // Logical implication. Failures identify a false consequent after a true
  // antecedent.
  Implies(Logic, Logic)
  // Negation. A failure means the child predicate unexpectedly held.
  Not(Logic)
  // Adds context around a child predicate without changing its truth value.
  Annotate(message~ : String, logic~ : Logic)
} derive(Eq, Debug)

///|
/// Constructor for an always-true condition.
pub fn Logic::top() -> Logic {
  Top
}

///|
/// Constructor for an always-false condition.
pub fn Logic::bot() -> Logic {
  Bot
}

///|
/// Lifts a plain Boolean into `Logic`.
pub fn Logic::boolean(value : Bool) -> Logic {
  Boolean(value)
}

///|
/// Builds a named predicate whose name appears in counterexamples when false.
pub fn Logic::predicate(name~ : String, value~ : Bool) -> Logic {
  Predicate(name~, value~)
}

///|
/// Adds a diagnostic frame around an existing condition.
pub fn Logic::annotate(self : Logic, message : String) -> Logic {
  Annotate(message~, logic=self)
}

///|
/// Evaluates the condition as a Boolean, discarding diagnostic information.
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
// Concatenates diagnostic messages while keeping their original left-to-right
// order. The order matters because it mirrors the structure of the failed
// predicate in formatted counterexamples.
fn merge_messages(left : Array[String], right : Array[String]) -> Array[String] {
  let messages = left.copy()
  for message in right {
    messages.push(message)
  }
  messages
}

///|
// Extracts only the explanations that are relevant to the failing branch.
// Successful branches intentionally return no messages so counterexamples do
// not include noise from predicates that already held.
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
/// Converts a failed condition into a structured counterexample.
pub fn Logic::counterexample(self : Logic) -> Counterexample {
  { messages: logic_failure_messages(self) }
}

///|
/// Evaluates the condition and preserves diagnostics on failure.
pub fn Logic::check(self : Logic) -> LogicValue {
  if self.eval() {
    Holds
  } else {
    Fails(self.counterexample())
  }
}

///|
/// Infix-friendly constructor for conjunction.
pub fn logic_and(left : Logic, right : Logic) -> Logic {
  And(left, right)
}

///|
/// Infix-friendly constructor for disjunction.
pub fn logic_or(left : Logic, right : Logic) -> Logic {
  Or(left, right)
}

///|
/// Infix-friendly constructor for implication.
pub fn logic_implies(left : Logic, right : Logic) -> Logic {
  Implies(left, right)
}

///|
/// Infix-friendly constructor for negation.
pub fn logic_not(logic : Logic) -> Logic {
  Not(logic)
}
