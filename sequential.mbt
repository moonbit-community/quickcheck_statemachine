///|
pub(all) struct RunReport[CSym, RSym, CCon, RCon] {
  seed : UInt64
  cases_run : Int
  commands_run : Int
  commands : Commands[CSym, RSym]
  history : History[CCon, RCon]
  labels : Array[String]
  command_distribution : Array[(String, Int)]
  shrinks : Int
  shrink_rounds : Int
} derive(Eq, Debug)

///|
pub(all) enum RunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  InvalidConfig(String)
  GenerationFailed(
    failure~ : GenerationFailure[MSym, CSym, RSym],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  InitFailed(
    commands~ : Commands[CSym, RSym],
    message~ : String,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  ReifyFailed(
    step_index~ : Int,
    symbolic_command~ : CSym,
    error~ : EnvError,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
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
  InvariantBroken(
    step_index~ : Int,
    model~ : MCon,
    logic~ : Logic,
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
  CleanupFailed(
    commands~ : Commands[CSym, RSym],
    history~ : History[CCon, RCon],
    message~ : String,
    shrinks~ : Int,
    shrink_rounds~ : Int
  )
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
fn error_message(error : Error) -> String {
  error.to_string()
}

///|
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
                  Ok(RunReport::{
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
            Ok(RunReport::{
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
            Ok(RunReport::{
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
