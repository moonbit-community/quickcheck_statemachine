///|
// Symbolic reference generation:
// Command programs are generated before concrete resources exist, so fresh
// variables must be deterministic and monotonic. This pins the variable sequence
// used by mock responses and dependency-aware shrinking.
test "gensym fresh vars are monotonic" {
  let gen = @quickcheck_statemachine.GenSym::new()
  let (first, gen) = gen.fresh()
  let (second, _) = gen.fresh()
  assert_eq(first.id, 0)
  assert_eq(second.id, 1)
}
