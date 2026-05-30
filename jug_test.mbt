// ref: https://stevana.github.io/the_sad_state_of_property-based_testing_libraries.html

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
fn jug_generator(
  model : JugModel,
  size : Int,
  rng : @splitmix.RandomState,
) -> JugCommand? {
  ignore(model)
  ignore(size)
  match rng.next_positive_int() % 6 {
    0 => Some(JugFillBig)
    1 => Some(JugFillSmall)
    2 => Some(JugEmptyBig)
    3 => Some(JugEmptySmall)
    4 => Some(JugSmallIntoBig)
    _ => Some(JugBigIntoSmall)
  }
}

///|
fn jug_search_spec() -> @quickcheck_statemachine.StateMachine[
  JugModel,
  JugModel,
  JugCommand,
  JugCommand,
  JugResponse,
  JugResponse,
  Unit,
  Unit,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => { big_jug: 0, small_jug: 0 },
    init_concrete_model=() => { big_jug: 0, small_jug: 0 },
    init_system=() => (),
    generator=jug_generator,
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
  let empty_big = jug_next(model, JugEmptyBig)
  let small_into_big = jug_next(model, JugSmallIntoBig)
  inspect(
    @debug.to_string([fill_small, empty_big, small_into_big]),
    content=(
      #|[
      #|  { big_jug: 1, small_jug: 3 },
      #|  { big_jug: 0, small_jug: 2 },
      #|  { big_jug: 3, small_jug: 0 },
      #|]
    ),
  )
}

///|
// Solution-as-counterexample search:
// The real command runner always returns `JugDone`. The postcondition expects
// `JugBigJugIs4` exactly when the model reaches four litres, so the runner
// reports a postcondition failure when random generation reaches the puzzle
// solution. Shrinking should then reduce the random program to the six-command
// Die Hard trace from the blog.
test "die hard jug reports the 4 liter solution" {
  let result = @quickcheck_statemachine.check(
    jug_search_spec(),
    config=case_config(cases=10000, max_commands=12),
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
        history~,
        logic~,
        shrinks~,
        shrink_rounds~,
        ..
      )
    ) else {
    fail("expected jug solution to be reported as a postcondition failure")
  }
  assert_true(shrinks > 0)
  assert_true(shrink_rounds > 0)
  assert_eq(commands.length(), 6)
  inspect(
    "\{step_index}: \{@debug.to_string(command)} -> \{@debug.to_string(response)}, model=\{@debug.to_string(model)}, next=\{@debug.to_string(next_model)}",
    content=(
      #|5: JugBigIntoSmall -> JugDone, model={ big_jug: 5, small_jug: 2 }, next={ big_jug: 4, small_jug: 3 }
    ),
  )
  inspect(
    @quickcheck_statemachine.format_commands(commands),
    content=(
      #|0: JugFillBig -> JugDone
      #|1: JugBigIntoSmall -> JugDone
      #|2: JugEmptySmall -> JugDone
      #|3: JugBigIntoSmall -> JugDone
      #|4: JugFillBig -> JugDone
      #|5: JugBigIntoSmall -> JugBigJugIs4
      #|
    ),
  )
  inspect(
    @quickcheck_statemachine.format_history(history),
    content=(
      #|Invocation(pid={ id: 0 }, command=JugFillBig)
      #|Response(pid={ id: 0 }, response=JugDone)
      #|Invocation(pid={ id: 1 }, command=JugBigIntoSmall)
      #|Response(pid={ id: 1 }, response=JugDone)
      #|Invocation(pid={ id: 2 }, command=JugEmptySmall)
      #|Response(pid={ id: 2 }, response=JugDone)
      #|Invocation(pid={ id: 3 }, command=JugBigIntoSmall)
      #|Response(pid={ id: 3 }, response=JugDone)
      #|Invocation(pid={ id: 4 }, command=JugFillBig)
      #|Response(pid={ id: 4 }, response=JugDone)
      #|Invocation(pid={ id: 5 }, command=JugBigIntoSmall)
      #|Response(pid={ id: 5 }, response=JugDone)
      #|
    ),
  )
  inspect(
    @quickcheck_statemachine.format_counterexample(logic.counterexample()),
    content="jug reports 4 liter solution",
  )
}
