///|
// Labelling coverage:
// The file-system article uses labels to audit whether generated programs cover
// semantically important scenarios. This helper-level test checks that duplicate
// labels are collapsed and that missing required command names are reported as
// coverage diagnostics.
test "labelling helpers collect coverage diagnostics" {
  let labels = @quickcheck_statemachine.collect_labels(["a", "b", "a"])
  assert_eq(labels.length(), 2)
  let missing = @quickcheck_statemachine.cover_command_names(
    [("open", 2), ("close", 1)],
    ["open", "read"],
  )
  assert_eq(missing.length(), 1)
  assert_eq(missing[0], "read")
}
