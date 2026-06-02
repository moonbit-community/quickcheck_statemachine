///|
// Logic diagnostics:
// QSM-style preconditions and postconditions are not plain booleans; they carry
// counterexample information so a failing command can explain which model
// predicate broke. This test checks that annotations survive through a compound
// predicate and are reported on failure.
test "logic reports annotated counterexamples" {
  let logic = @quickcheck_statemachine.logic_and(
    @quickcheck_statemachine.Logic::top(),
    @quickcheck_statemachine.Logic::boolean(false).annotate("expected failure"),
  )
  assert_true(logic.eval() == false)
  guard logic.check() is Fails(counterexample) else {
    fail("expected logic failure")
  }
  assert_eq(counterexample.messages.length(), 2)
  assert_eq(counterexample.messages[0], "expected failure")
}
