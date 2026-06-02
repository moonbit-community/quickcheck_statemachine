///|
/// Async-only failures for true parallel replay.
///
/// Synchronous replay failures stay in `RunFailure` and are wrapped in
/// `ReplayFailed`. Linearization, search budget, and branch merge failures are
/// represented here so the existing synchronous public enum remains unchanged.
pub(all) enum AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  ReplayFailed(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym]?,
    failure~ : @qsm.RunFailure[MSym, MCon, CSym, CCon, RSym, RCon]
  )
  LinearizationFailed(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym],
    commands~ : @qsm.Commands[CSym, RSym],
    history~ : @qsm.History[CCon, RCon],
    logic~ : @qsm.Logic,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  LinearizationBudgetExceeded(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym],
    commands~ : @qsm.Commands[CSym, RSym],
    history~ : @qsm.History[CCon, RCon],
    operation_count~ : Int,
    max_operations~ : Int,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  BranchEnvironmentMergeFailed(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym],
    commands~ : @qsm.Commands[CSym, RSym],
    history~ : @qsm.History[CCon, RCon],
    error~ : @qsm.EnvError,
    logic~ : @qsm.Logic,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
} derive(Eq, Debug)

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon] wrap_replay_failure(
  parallel_commands : @qsm.ParallelCommands[CSym, RSym]?,
  failure : @qsm.RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
) -> AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  ReplayFailed(parallel_commands~, failure~)
}
