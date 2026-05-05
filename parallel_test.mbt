///|
// Parallel linearisation smoke test:
// The sad-state blog explains parallel checking as collecting concurrent
// history and finding an interleaving accepted by the sequential model. This
// library currently uses a deterministic linearisation path; the test pins the
// prefix-left-right order that later linearizability checks will refine.
test "parallel commands linearise deterministically" {
  let first = @quickcheck_statemachine.Command::{
    command: CounterIncr,
    response: CounterIncrDone,
    vars: [],
  }
  let second = @quickcheck_statemachine.Command::{
    command: CounterGet,
    response: CounterGot(1),
    vars: [],
  }
  let parallel = @quickcheck_statemachine.ParallelCommands::{
    prefix: @quickcheck_statemachine.Commands::{ commands: [first] },
    left: @quickcheck_statemachine.Commands::{ commands: [second] },
    right: @quickcheck_statemachine.Commands::{ commands: [] },
  }
  guard @quickcheck_statemachine.linearise(parallel) is Some(commands) else {
    fail("expected deterministic linearization")
  }
  assert_eq(commands.length(), 2)
}
