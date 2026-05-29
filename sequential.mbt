///|
/// Summary of a successful generation or replay.
///
/// Reports keep both the symbolic command program and the concrete history. The
/// symbolic program is what should be saved or shrunk; the history is what the
/// system actually did while replaying that program.
pub(all) struct RunReport[CSym, RSym, CCon, RCon] {
  // Seed used for the first generated case.
  seed : UInt64
  // Number of cases completed by `check`, or 1 for direct replay.
  cases_run : Int
  // Total number of concrete commands executed.
  commands_run : Int
  // Last generated or replayed symbolic program.
  commands : Commands[CSym, RSym]
  // Concrete invocation/response trace from the last replay.
  history : History[CCon, RCon]
  // Deduplicated semantic labels observed during replay.
  labels : Array[String]
  // Command-name counts for the symbolic program.
  command_distribution : Array[(String, Int)]
  // Number of accepted shrink steps used before this report was produced.
  shrinks : Int
  // Number of shrink rounds used before this report was produced.
  shrink_rounds : Int
} derive(Eq, Debug)

///|
/// Failures that can occur while generating, replaying, checking, or shrinking.
///
/// Each failure stores the symbolic program and concrete history whenever they
/// are available, so a user can inspect the minimized counterexample in the same
/// style as QSM's sequential property output.
pub(all) enum RunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  // The run configuration is invalid before any command is generated.
  InvalidConfig(String)
  // Symbolic generation failed before a runnable program was available.
  GenerationFailed(
    failure~ : GenerationFailure[MSym, CSym, RSym],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // The mutable system under test could not be initialized.
  InitFailed(
    commands~ : Commands[CSym, RSym],
    message~ : String,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // A symbolic command mentioned a variable missing from the execution
  // environment.
  ReifyFailed(
    step_index~ : Int,
    symbolic_command~ : CSym,
    error~ : EnvError,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // `run_command` raised while executing the concrete command.
  ExecutionFailed(
    step_index~ : Int,
    command~ : CCon,
    symbolic_command~ : CSym,
    model~ : MCon,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    message~ : String,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // The concrete response could not be matched with the symbolic response that
  // predicted fresh variables.
  BindFailed(
    step_index~ : Int,
    symbolic_response~ : RSym,
    response~ : RCon,
    error~ : BindError,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // The model rejected the concrete response for this command.
  PostconditionFailed(
    step_index~ : Int,
    command~ : CCon,
    symbolic_command~ : CSym,
    response~ : RCon,
    model~ : MCon,
    next_model~ : MCon,
    logic~ : Logic,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // The model-wide invariant failed after a successful command transition.
  InvariantBroken(
    step_index~ : Int,
    model~ : MCon,
    logic~ : Logic,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // Cleanup raised after replay. The command history is still preserved.
  CleanupFailed(
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    message~ : String,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  // Execution succeeded, but required labels or command names were not covered.
  CoverageFailed(
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    missing_labels~ : Array[String],
    missing_command_names~ : Array[String],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
} derive(Eq, Debug)

///|
// Normalizes any raised MoonBit error into a message that can be stored in
// `RunFailure`.
fn error_message(error : Error) -> String {
  error.to_string()
}

///|
// Rewrites the shrink counters inside a failure after minimization has finished.
fn[MSym, MCon, CSym, CCon, RSym, RCon] with_shrink_stats(
  failure : RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
  shrinks : Int,
  shrink_rounds : Int,
) -> RunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  match failure {
    InvalidConfig(message) => InvalidConfig(message)
    GenerationFailed(failure~, ..) =>
      GenerationFailed(failure~, shrinks~, shrink_rounds~)
    InitFailed(commands~, message~, ..) =>
      InitFailed(commands~, message~, shrinks~, shrink_rounds~)
    ReifyFailed(step_index~, symbolic_command~, error~, commands~, history~, ..) =>
      ReifyFailed(
        step_index~,
        symbolic_command~,
        error~,
        commands~,
        history~,
        shrinks~,
        shrink_rounds~,
      )
    ExecutionFailed(
      step_index~,
      command~,
      symbolic_command~,
      model~,
      commands~,
      history~,
      message~,
      ..
    ) =>
      ExecutionFailed(
        step_index~,
        command~,
        symbolic_command~,
        model~,
        commands~,
        history~,
        message~,
        shrinks~,
        shrink_rounds~,
      )
    BindFailed(
      step_index~,
      symbolic_response~,
      response~,
      error~,
      commands~,
      history~,
      ..
    ) =>
      BindFailed(
        step_index~,
        symbolic_response~,
        response~,
        error~,
        commands~,
        history~,
        shrinks~,
        shrink_rounds~,
      )
    PostconditionFailed(
      step_index~,
      command~,
      symbolic_command~,
      response~,
      model~,
      next_model~,
      logic~,
      commands~,
      history~,
      ..
    ) =>
      PostconditionFailed(
        step_index~,
        command~,
        symbolic_command~,
        response~,
        model~,
        next_model~,
        logic~,
        commands~,
        history~,
        shrinks~,
        shrink_rounds~,
      )
    InvariantBroken(step_index~, model~, logic~, commands~, history~, ..) =>
      InvariantBroken(
        step_index~,
        model~,
        logic~,
        commands~,
        history~,
        shrinks~,
        shrink_rounds~,
      )
    CleanupFailed(commands~, history~, message~, ..) =>
      CleanupFailed(commands~, history~, message~, shrinks~, shrink_rounds~)
    CoverageFailed(
      commands~,
      history~,
      missing_labels~,
      missing_command_names~,
      ..
    ) =>
      CoverageFailed(
        commands~,
        history~,
        missing_labels~,
        missing_command_names~,
        shrinks~,
        shrink_rounds~,
      )
  }
}

///|
// Best-effort cleanup used on failure paths. A cleanup error must not hide the
// original failing command, because that original failure is the useful
// counterexample.
fn[S, MCon] cleanup_after_failure(
  cleanup : (MCon, S) -> Unit raise,
  model : MCon,
  system : S,
) -> Unit {
  try cleanup(model, system) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
// Computes missing required labels after replay.
fn missing_required_values(
  required : Array[String],
  values : Array[String],
) -> Array[String] {
  let missing : Array[String] = []
  for required_value in required {
    if !contains_string(values, required_value) {
      missing.push(required_value)
    }
  }
  missing
}

///|
/// Replays a symbolic command program against the concrete system.
///
/// This is the sequential property loop from QSM:
///
/// 1. initialize the system, concrete model, environment, and history;
/// 2. reify each symbolic command through the environment;
/// 3. execute the concrete command and record invocation/response history;
/// 4. check the postcondition against the pre-state model;
/// 5. bind newly returned concrete references into the environment;
/// 6. advance/check the concrete model and collect coverage labels.
///
/// The generated program already satisfied symbolic preconditions; replay does
/// not re-check them because its job is to compare the implementation with the
/// concrete model.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_commands(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
  config? : RunConfig = RunConfig::default(),
) -> Result[
  RunReport[CSym, RSym, CCon, RCon],
  RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match validate_generation_config(config) {
    Some(message) => Err(InvalidConfig(message))
    None => {
      let system_result = try (spec.init_system)() catch {
        error => Err(error_message(error))
      } noraise {
        system => Ok(system)
      }
      match system_result {
        Err(message) =>
          Err(InitFailed(commands~, message~, shrinks=0, shrink_rounds=0))
        Ok(system) => {
          let initial_history : History[CCon, RCon] = History::empty()
          let labels : Array[String] = []
          for step_index = 0, model = (spec.init_concrete_model)(), environment = Environment::empty(), history = initial_history; step_index <
             commands.commands.length(); {
            let symbolic = commands.commands[step_index]
            // Reification is the point where `Ref::Symbolic(v)` values become
            // `Ref::Concrete(value)` values returned by earlier commands.
            match (spec.reify_command)(symbolic.command, environment) {
              Err(error) => {
                cleanup_after_failure(spec.cleanup, model, system)
                break Err(
                  ReifyFailed(
                    step_index~,
                    symbolic_command=symbolic.command,
                    error~,
                    commands~,
                    history~,
                    shrinks=0,
                    shrink_rounds=0,
                  ),
                )
              }
              Ok(concrete_command) => {
                let pid = Pid::{ id: step_index }
                let invoked = history.push(
                  Invocation(pid~, command=concrete_command),
                )
                // User semantics can raise, for example when a file system,
                // database, or service call fails unexpectedly.
                let run_result = try
                  (spec.run_command)(concrete_command, system)
                catch {
                  error => Err(error_message(error))
                } noraise {
                  response => Ok(response)
                }
                match run_result {
                  Err(message) => {
                    let failed_history = invoked.push(Exception(pid~, message~))
                    cleanup_after_failure(spec.cleanup, model, system)
                    break Err(
                      ExecutionFailed(
                        step_index~,
                        command=concrete_command,
                        symbolic_command=symbolic.command,
                        model~,
                        commands~,
                        history=failed_history,
                        message~,
                        shrinks=0,
                        shrink_rounds=0,
                      ),
                    )
                  }
                  Ok(concrete_response) => {
                    let responded = invoked.push(
                      Response(pid~, response=concrete_response),
                    )
                    // Compute the next model before checking the postcondition
                    // so a failure can report both the previous and next model.
                    let next_model = (spec.transition_concrete)(
                      model, concrete_command, concrete_response,
                    )
                    let postcondition = (spec.postcondition)(
                      model, concrete_command, concrete_response,
                    )
                    if !postcondition.eval() {
                      cleanup_after_failure(spec.cleanup, model, system)
                      break Err(
                        PostconditionFailed(
                          step_index~,
                          command=concrete_command,
                          symbolic_command=symbolic.command,
                          response=concrete_response,
                          model~,
                          next_model~,
                          logic=postcondition,
                          commands~,
                          history=responded,
                          shrinks=0,
                          shrink_rounds=0,
                        ),
                      )
                    }
                    match
                      (spec.bind_response)(
                        symbolic.response,
                        concrete_response,
                        environment,
                      ) {
                      Err(error) => {
                        cleanup_after_failure(spec.cleanup, model, system)
                        break Err(
                          BindFailed(
                            step_index~,
                            symbolic_response=symbolic.response,
                            response=concrete_response,
                            error~,
                            commands~,
                            history=responded,
                            shrinks=0,
                            shrink_rounds=0,
                          ),
                        )
                      }
                      Ok(next_environment) => {
                        // Invariants describe model-wide properties that
                        // should hold after every successful transition.
                        let invariant = (spec.invariant)(next_model)
                        if !invariant.eval() {
                          cleanup_after_failure(
                            spec.cleanup,
                            next_model,
                            system,
                          )
                          break Err(
                            InvariantBroken(
                              step_index~,
                              model=next_model,
                              logic=invariant,
                              commands~,
                              history=responded,
                              shrinks=0,
                              shrink_rounds=0,
                            ),
                          )
                        }
                        for
                          label in (spec.label)(
                            model, concrete_command, concrete_response,
                          ) {
                          labels.push(label)
                        }
                        continue step_index + 1,
                          next_model,
                          next_environment,
                          responded
                      }
                    }
                  }
                }
              }
            }
          } nobreak {
            let cleanup_result = try (spec.cleanup)(model, system) catch {
              error => Err(error_message(error))
            } noraise {
              _ => Ok(())
            }
            match cleanup_result {
              Err(message) =>
                Err(
                  CleanupFailed(
                    commands~,
                    history~,
                    message~,
                    shrinks=0,
                    shrink_rounds=0,
                  ),
                )
              Ok(_) => {
                // Coverage is checked after successful replay so it does not
                // mask a real semantic failure in the system under test.
                let unique_labels = collect_labels(labels)
                let distribution = command_names(commands, spec.command_name)
                let missing_labels = missing_required_values(
                  config.required_labels,
                  unique_labels,
                )
                let missing_command_names = cover_command_names(
                  distribution,
                  config.required_command_names,
                )
                if missing_labels.length() > 0 ||
                  missing_command_names.length() > 0 {
                  Err(
                    CoverageFailed(
                      commands~,
                      history~,
                      missing_labels~,
                      missing_command_names~,
                      shrinks=0,
                      shrink_rounds=0,
                    ),
                  )
                } else {
                  Ok({
                    seed: config.seed,
                    cases_run: 1,
                    commands_run: commands.length(),
                    commands,
                    history,
                    labels: unique_labels,
                    command_distribution: distribution,
                    shrinks: 0,
                    shrink_rounds: 0,
                  })
                }
              }
            }
          }
        }
      }
    }
  }
}

///|
/// Alias for replaying a previously generated symbolic command program.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] replay(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
  config? : RunConfig = RunConfig::default(),
) -> Result[
  RunReport[CSym, RSym, CCon, RCon],
  RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  run_commands(spec, commands, config~)
}

///|
// Minimizes a failing program by repeatedly accepting the first smaller
// candidate that still fails.
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] shrink_failure(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
  config : RunConfig,
) -> (Commands[CSym, RSym], Int, Int) {
  for round = 0, current = commands, shrinks = 0; round <
     config.max_shrink_rounds &&
     shrinks < config.max_shrinks; {
    let candidates = shrink_commands_once(spec, current)
    let next = first_failing_candidate(spec, candidates, config)
    match next {
      None => break (current, shrinks, round)
      Some(candidate) => continue round + 1, candidate, shrinks + 1
    }
  } nobreak {
    (current, shrinks, config.max_shrink_rounds)
  }
}

///|
/// Generates and executes many state-machine programs.
///
/// Each case uses a deterministic seed derived from `config.seed`. On the first
/// semantic failure, `check` optionally shrinks the generated program and then
/// returns the minimized failure. Coverage failures are not shrunk because they
/// mean a successful run did not include required scenarios, not that a smaller
/// counterexample should be found.
pub fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] check(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
) -> Result[
  RunReport[CSym, RSym, CCon, RCon],
  RunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match validate_generation_config(config) {
    Some(message) => Err(InvalidConfig(message))
    None =>
      for case_index = 0, commands_run = 0, last_report = None; case_index <
         config.cases; {
        let case_seed = config.seed + case_index.to_uint64()
        match generate_commands_with_seed(spec, config~, seed=case_seed) {
          Err(failure) =>
            break Err(GenerationFailed(failure~, shrinks=0, shrink_rounds=0))
          Ok(commands) =>
            match run_commands(spec, commands, config~) {
              Ok(report) =>
                continue case_index + 1,
                  commands_run + report.commands_run,
                  Some(report)
              Err(failure) =>
                if failure is CoverageFailed(..) {
                  break Err(failure)
                } else if config.shrink {
                  let (shrunk, shrinks, rounds) = shrink_failure(
                    spec, commands, config,
                  )
                  match run_commands(spec, shrunk, config~) {
                    Ok(_) =>
                      break Err(with_shrink_stats(failure, shrinks, rounds))
                    Err(final_failure) =>
                      break Err(
                        with_shrink_stats(final_failure, shrinks, rounds),
                      )
                  }
                } else {
                  break Err(failure)
                }
            }
        }
      } nobreak {
        match last_report {
          Some(report) =>
            Ok({
              seed: config.seed,
              cases_run: config.cases,
              commands_run,
              commands: report.commands,
              history: report.history,
              labels: report.labels,
              command_distribution: report.command_distribution,
              shrinks: 0,
              shrink_rounds: 0,
            })
          None =>
            Ok({
              seed: config.seed,
              cases_run: config.cases,
              commands_run,
              commands: Commands::empty(),
              history: History::empty(),
              labels: [],
              command_distribution: [],
              shrinks: 0,
              shrink_rounds: 0,
            })
        }
      }
  }
}

///|
/// Runs `check` and raises on failure.
///
/// This is convenient inside MoonBit tests where a failing property should fail
/// the test immediately.
pub fn[
  MSym : @debug.Debug,
  MCon : @debug.Debug,
  CSym : @debug.Debug,
  CCon : @debug.Debug,
  RSym : @debug.Debug,
  RCon : @debug.Debug,
  V,
  S,
] assert_check(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config? : RunConfig = RunConfig::default(),
) -> RunReport[CSym, RSym, CCon, RCon] raise {
  match check(spec, config~) {
    Ok(report) => report
    Err(failure) =>
      fail("state machine check failed: \{@debug.to_string(failure)}")
  }
}

///|
/// Runs `replay` and raises on failure.
///
/// Use this for checked-in regression programs or minimized counterexamples.
pub fn[
  MSym : @debug.Debug,
  MCon : @debug.Debug,
  CSym : @debug.Debug,
  CCon : @debug.Debug,
  RSym : @debug.Debug,
  RCon : @debug.Debug,
  V,
  S,
] assert_replay(
  spec : StateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : Commands[CSym, RSym],
  config? : RunConfig = RunConfig::default(),
) -> RunReport[CSym, RSym, CCon, RCon] raise {
  match replay(spec, commands, config~) {
    Ok(report) => report
    Err(failure) =>
      fail("state machine replay failed: \{@debug.to_string(failure)}")
  }
}
