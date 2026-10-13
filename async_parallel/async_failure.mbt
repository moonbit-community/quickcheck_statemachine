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
    shrinks~ : Int32,
    shrink_rounds~ : Int32
  )
  LinearizationBudgetExceeded(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym],
    commands~ : @qsm.Commands[CSym, RSym],
    history~ : @qsm.History[CCon, RCon],
    operation_count~ : Int32,
    max_operations~ : Int32,
    shrinks~ : Int32,
    shrink_rounds~ : Int32
  )
  BranchEnvironmentMergeFailed(
    parallel_commands~ : @qsm.ParallelCommands[CSym, RSym],
    commands~ : @qsm.Commands[CSym, RSym],
    history~ : @qsm.History[CCon, RCon],
    error~ : @qsm.EnvError,
    logic~ : @qsm.Logic,
    shrinks~ : Int32,
    shrink_rounds~ : Int32
  )
} derive(Eq, Debug)

///|
pub extend AsyncRunFailure with Eq::{not_equal, equal}

///|
pub extend AsyncRunFailure with Debug::{to_repr}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon] wrap_replay_failure(
  parallel_commands : @qsm.ParallelCommands[CSym, RSym]?,
  failure : @qsm.RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
) -> AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  ReplayFailed(parallel_commands~, failure~)
}
