///|
// Die Hard jug model and property:
// The model is only the amount of water in the 5L
// and 3L jugs. Commands are the legal jug actions, and the interesting
// "failure" is reaching a state where the big jug contains exactly 4L; the
// failing command program is therefore the puzzle solution.
struct JugModel {
  big_jug : Int
  small_jug : Int
} derive(Eq, Debug)

///|
enum JugCommand {
  JugFillBig
  JugFillSmall
  JugEmptyBig
  JugEmptySmall
  JugSmallIntoBig
  JugBigIntoSmall
} derive(Eq, Debug)

///|
enum JugResponse {
  JugDone
  JugBigJugIs4
} derive(Eq, Debug)

///|
fn jug_next(model : JugModel, command : JugCommand) -> JugModel {
  match command {
    JugFillBig => { big_jug: 5, small_jug: model.small_jug }
    JugFillSmall => { big_jug: model.big_jug, small_jug: 3 }
    JugEmptyBig => { big_jug: 0, small_jug: model.small_jug }
    JugEmptySmall => { big_jug: model.big_jug, small_jug: 0 }
    JugSmallIntoBig => {
      let big_jug = (model.big_jug + model.small_jug).min(5)
      { big_jug, small_jug: model.small_jug - (big_jug - model.big_jug) }
    }
    JugBigIntoSmall => {
      let small_jug = (model.big_jug + model.small_jug).min(3)
      { big_jug: model.big_jug - (small_jug - model.small_jug), small_jug }
    }
  }
}

///|
fn jug_expected(next_model : JugModel) -> JugResponse {
  if next_model.big_jug == 4 {
    JugBigJugIs4
  } else {
    JugDone
  }
}

///|
fn jug_name(command : JugCommand) -> String {
  match command {
    JugFillBig => "fill-big"
    JugFillSmall => "fill-small"
    JugEmptyBig => "empty-big"
    JugEmptySmall => "empty-small"
    JugSmallIntoBig => "small-into-big"
    JugBigIntoSmall => "big-into-small"
  }
}

///|
fn jug_solution_spec() -> @quickcheck_statemachine.StateMachine[
  JugModel,
  JugModel,
  JugCommand,
  JugCommand,
  JugResponse,
  JugResponse,
  Unit,
  Unit,
] {
  let commands : Array[JugCommand] = [
    JugFillBig,
    JugBigIntoSmall,
    JugEmptySmall,
    JugBigIntoSmall,
    JugFillBig,
    JugBigIntoSmall,
  ]
  let cursor : Array[Int] = [0]
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => { big_jug: 0, small_jug: 0 },
    init_concrete_model=() => { big_jug: 0, small_jug: 0 },
    init_system=() => (),
    generator=(model, size, rng) => {
      ignore(model)
      ignore(size)
      ignore(rng)
      let index = cursor[0]
      if index < commands.length() {
        cursor[0] = index + 1
        Some(commands[index])
      } else {
        None
      }
    },
    mock=(model, command, gen_sym) => {
      (jug_expected(jug_next(model, command)), gen_sym)
    },
    transition_symbolic=(model, command, response) => {
      ignore(response)
      jug_next(model, command)
    },
    transition_concrete=(model, command, response) => {
      ignore(response)
      jug_next(model, command)
    },
    reify_command=(command, environment) => {
      ignore(environment)
      Ok(command)
    },
    run_command=(command, system) => {
      ignore(command)
      ignore(system)
      JugDone
    },
    bind_response=(symbolic, concrete, environment) => {
      ignore(symbolic)
      ignore(concrete)
      Ok(environment)
    },
    postcondition=(model, command, response) => {
      @quickcheck_statemachine.Logic::predicate(
        name="jug reports 4 liter solution",
        value=response == jug_expected(jug_next(model, command)),
      )
    },
    command_name=jug_name,
  )
}

///|
// Transition sanity checks:
// These assertions document the arithmetic of the fake model itself. They cover
// fill, empty, and pour actions so the later solution test can rely on
// `jug_next` as the reference transition relation.
test "die hard jug model covers alternate commands" {
  let model = JugModel::{ big_jug: 1, small_jug: 2 }
  let fill_small = jug_next(model, JugFillSmall)
  assert_eq(fill_small.big_jug, 1)
  assert_eq(fill_small.small_jug, 3)
  let empty_big = jug_next(model, JugEmptyBig)
  assert_eq(empty_big.big_jug, 0)
  assert_eq(empty_big.small_jug, 2)
  let small_into_big = jug_next(model, JugSmallIntoBig)
  assert_eq(small_into_big.big_jug, 3)
  assert_eq(small_into_big.small_jug, 0)
}

///|
// Solution-as-counterexample regression:
// The real command runner always returns `JugDone`. The postcondition expects
// `JugBigJugIs4` exactly when the model reaches four litres, so the runner
// reports a postcondition failure at the final pour. This checks that a pure
// state machine can be used to search for a witness, not only to compare a fake
// against an implementation.
test "die hard jug reports the 4 liter solution" {
  let result = @quickcheck_statemachine.check(
    jug_solution_spec(),
    config=case_config(max_commands=6),
  )
  guard result
    is Err(
      PostconditionFailed(
        step_index~,
        command~,
        response~,
        model~,
        next_model~,
        commands~,
        ..
      )
    ) else {
    fail("expected jug solution to be reported as a postcondition failure")
  }
  assert_eq(step_index, 5)
  assert_true(command is JugBigIntoSmall)
  assert_true(response is JugDone)
  assert_eq(model.big_jug, 5)
  assert_eq(model.small_jug, 2)
  assert_eq(next_model.big_jug, 4)
  assert_eq(next_model.small_jug, 3)
  assert_eq(commands.length(), 6)
  assert_true(commands.commands[4].command is JugFillBig)
}
