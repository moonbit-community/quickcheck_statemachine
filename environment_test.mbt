///|
// Execution environment:
// During replay, symbolic variables from the generated program are bound to
// concrete values returned by the system. This test covers insertion, lookup,
// missing-variable errors, and merging disjoint environments.
test "environment lookup insert merge" {
  let first = @quickcheck_statemachine.Environment::empty()
  let v0 = @quickcheck_statemachine.Var::{ id: 0 }
  let v1 = @quickcheck_statemachine.Var::{ id: 1 }
  let first = first.insert(v0, 10)
  assert_true(first.contains(v0))
  guard first.lookup(v0) is Ok(10) else { fail("expected v0 binding") }
  let second = @quickcheck_statemachine.Environment::empty().insert(v1, 20)
  let merged = first.merge(second)
  guard merged is Ok(env) else { fail("expected merge to succeed") }
  guard env.lookup(v1) is Ok(20) else { fail("expected v1 binding") }
  assert_true(env.lookup(@quickcheck_statemachine.Var::{ id: 9 }) is Err(_))
}
