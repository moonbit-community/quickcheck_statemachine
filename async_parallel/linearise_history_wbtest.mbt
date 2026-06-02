///|
enum LCommand {
  LIncr
  LGet
} derive(Eq, Debug)

///|
enum LResponse {
  LUnit
  LValue(Int)
} derive(Eq, Debug)

///|
fn l_expected(model : Int, command : LCommand) -> LResponse {
  match command {
    LIncr => LUnit
    LGet => LValue(model)
  }
}

///|
fn l_transition(model : Int, command : LCommand, response : LResponse) -> Int {
  ignore(response)
  match command {
    LIncr => model + 1
    LGet => model
  }
}

///|
fn l_spec() -> AsyncStateMachine[
  Int,
  Int,
  LCommand,
  LCommand,
  LResponse,
  LResponse,
  Unit,
  Unit,
] {
  AsyncStateMachine::new(
    init_symbolic_model=() => 0,
    init_concrete_model=() => 0,
    init_system=() => (),
    generator=(_, _, _) => None,
    mock=(model, command, gen_sym) => (l_expected(model, command), gen_sym),
    transition_symbolic=l_transition,
    transition_concrete=l_transition,
    reify_command=(command, _) => Ok(command),
    run_command=(command, _) => l_expected(0, command),
    bind_response=(_, _, environment) => Ok(environment),
    postcondition=(model, command, response) => {
      @qsm.Logic::predicate(
        name="linearise response matches model",
        value=response == l_expected(model, command),
      )
    },
  )
}

///|
fn l_history(
  events : Array[@qsm.HistoryEvent[LCommand, LResponse]],
) -> @qsm.History[LCommand, LResponse] {
  @qsm.History::{ events, }
}

///|
fn l_inv(
  id : Int,
  command : LCommand,
) -> @qsm.HistoryEvent[LCommand, LResponse] {
  @qsm.Invocation(pid=@qsm.Pid::{ id, }, command~)
}

///|
fn l_resp(
  id : Int,
  response : LResponse,
) -> @qsm.HistoryEvent[LCommand, LResponse] {
  @qsm.Response(pid=@qsm.Pid::{ id, }, response~)
}

///|
test "sequential history linearises" {
  let history = l_history([
    l_inv(0, LIncr),
    l_resp(0, LUnit),
    l_inv(1, LGet),
    l_resp(1, LValue(1)),
  ])
  match linearise_history(l_spec(), 0, history, 6) {
    Linearised(model~, ..) => assert_eq(model, 1)
    _ => fail("expected linearization success")
  }
}

///|
test "overlap history can choose legal order" {
  let history = l_history([
    l_inv(0, LIncr),
    l_inv(1, LGet),
    l_resp(1, LValue(0)),
    l_resp(0, LUnit),
  ])
  match linearise_history(l_spec(), 0, history, 6) {
    Linearised(model~, ..) => assert_eq(model, 1)
    _ => fail("expected overlap linearization success")
  }
}

///|
test "real time order is respected" {
  let history = l_history([
    l_inv(0, LIncr),
    l_resp(0, LUnit),
    l_inv(1, LGet),
    l_resp(1, LValue(0)),
  ])
  match linearise_history(l_spec(), 0, history, 6) {
    NotLinearizable(..) => ()
    _ => fail("expected linearization failure")
  }
}

///|
test "impossible response fails linearization" {
  let history = l_history([l_inv(0, LGet), l_resp(0, LValue(42))])
  match linearise_history(l_spec(), 0, history, 6) {
    NotLinearizable(..) => ()
    _ => fail("expected impossible response failure")
  }
}

///|
test "linearization budget is bounded" {
  let events : Array[@qsm.HistoryEvent[LCommand, LResponse]] = []
  for index in 0..<7 {
    events.push(l_inv(index, LIncr))
  }
  for index in 0..<7 {
    events.push(l_resp(index, LUnit))
  }
  match linearise_history(l_spec(), 0, l_history(events), 6) {
    BudgetExceeded(operation_count~, max_operations~) => {
      assert_eq(operation_count, 7)
      assert_eq(max_operations, 6)
    }
    _ => fail("expected budget exceeded")
  }
}
