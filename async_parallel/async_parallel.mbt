///|
fn max_parallel_operations() -> Int32 {
  6
}

///|
fn error_message(error : Error) -> String {
  error.to_string()
}

///|
// Mirrors the root package validation helper without exposing new sync API.
fn validate_generation_config(config : @qsm.RunConfig) -> String? {
  if config.cases < 0 {
    Some("cases must be non-negative")
  } else if config.max_commands < 0 {
    Some("max_commands must be non-negative")
  } else if config.size < 0 {
    Some("size must be non-negative")
  } else if config.max_tries <= 0 {
    Some("max_tries must be positive")
  } else if config.max_shrinks < 0 {
    Some("max_shrinks must be non-negative")
  } else if config.max_shrink_rounds < 0 {
    Some("max_shrink_rounds must be non-negative")
  } else {
    None
  }
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
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
fn[CSym, RSym] take_commands(
  commands : @qsm.Commands[CSym, RSym],
  start : Int32,
  end : Int32,
) -> @qsm.Commands[CSym, RSym] {
  let taken : Array[@qsm.Command[CSym, RSym]] = []
  for index in start..<end {
    taken.push(commands.commands[index])
  }
  @qsm.Commands::{ commands: taken, }
}

///|
fn[CSym, RSym] commands_from_array(
  commands : Array[@qsm.Command[CSym, RSym]],
) -> @qsm.Commands[CSym, RSym] {
  @qsm.Commands::{ commands: commands.copy(), }
}

///|
fn[CSym, RSym] flatten_parallel_commands(
  commands : @qsm.ParallelCommands[CSym, RSym],
) -> @qsm.Commands[CSym, RSym] {
  @qsm.Commands::concat(
    @qsm.Commands::concat(commands.prefix, commands.left),
    commands.right,
  )
}

///|
fn[C, R] history_from_events(
  events : Array[@qsm.HistoryEvent[C, R]],
) -> @qsm.History[C, R] {
  @qsm.History::{ events: events.copy(), }
}

///|
fn[C, R] append_history_events(
  history : @qsm.History[C, R],
  events : Array[@qsm.HistoryEvent[C, R]],
) -> @qsm.History[C, R] {
  let merged = history.events.copy()
  for event in events {
    merged.push(event)
  }
  @qsm.History::{ events: merged, }
}

///|
fn[V] copy_environment(
  environment : @qsm.Environment[V],
) -> @qsm.Environment[V] {
  @qsm.Environment::{ bindings: environment.bindings.copy(), }
}

///|
fn[V] environment_delta(
  base : @qsm.Environment[V],
  updated : @qsm.Environment[V],
) -> @qsm.Environment[V] {
  let bindings : Map[@qsm.Var, V] = Map([])
  for variable, value in updated.bindings {
    if !base.bindings.contains(variable) {
      bindings[variable] = value
    }
  }
  @qsm.Environment::{ bindings, }
}

///|
priv enum Selection[CSym] {
  Stop
  Selected(CSym)
  Exhausted(@qsm.Logic?)
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] select_symbolic_command(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  model : MSym,
  size : Int32,
  rng : @splitmix.RandomState,
  max_tries : Int32,
) -> Selection[CSym] {
  for tries = 0, last_precondition = None; tries < max_tries; {
    match (spec.generator)(model, size, rng) {
      None => break Stop
      Some(command) => {
        let precondition = (spec.precondition)(model, command)
        if precondition.eval() {
          break Selected(command)
        } else {
          continue tries + 1, Some(precondition)
        }
      }
    }
  } nobreak {
    Exhausted(last_precondition)
  }
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_commands_with_seed_async_spec(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config~ : @qsm.RunConfig = @qsm.RunConfig::default(),
  seed~ : UInt64 = config.seed,
) -> Result[@qsm.Commands[CSym, RSym], @qsm.GenerationFailure[MSym, CSym, RSym]] {
  match validate_generation_config(config) {
    Some(message) => Err(@qsm.InvalidGenerationConfig(message))
    None => {
      let rng = @splitmix.RandomState(seed~)
      let initial_commands : @qsm.Commands[CSym, RSym] = @qsm.Commands::empty()
      for step_index = 0, model = (spec.init_symbolic_model)(), gen_sym = @qsm.GenSym::new(), commands = initial_commands; step_index <
         config.max_commands; {
        match
          select_symbolic_command(
            spec,
            model,
            config.size,
            rng,
            config.max_tries,
          ) {
          Stop => break Ok(commands)
          Exhausted(last_precondition) =>
            break Err(
              @qsm.Deadlock(step_index~, model~, commands~, last_precondition~),
            )
          Selected(symbolic_command) => {
            let (symbolic_response, next_gen_sym) = (spec.mock)(
              model, symbolic_command, gen_sym,
            )
            let vars = (spec.response_vars)(symbolic_response)
            let command = @qsm.Command::{
              command: symbolic_command,
              response: symbolic_response,
              vars,
            }
            let next_model = (spec.transition_symbolic)(
              model,
              command.command,
              command.response,
            )
            continue step_index + 1,
              next_model,
              next_gen_sym,
              commands.append(command)
          }
        }
      } nobreak {
        Ok(commands)
      }
    }
  }
}

///|
fn[CSym, RSym] without_command_index(
  commands : Array[@qsm.Command[CSym, RSym]],
  index : Int32,
) -> Array[@qsm.Command[CSym, RSym]] {
  let remaining : Array[@qsm.Command[CSym, RSym]] = []
  for current_index, command in commands {
    if current_index != index {
      remaining.push(command)
    }
  }
  remaining
}

///|
fn[CSym, RSym] command_permutations(
  commands : Array[@qsm.Command[CSym, RSym]],
) -> Array[Array[@qsm.Command[CSym, RSym]]] {
  if commands.length() == 0 {
    [[]]
  } else {
    let result : Array[Array[@qsm.Command[CSym, RSym]]] = []
    for index, command in commands {
      let rest = without_command_index(commands, index)
      for suffix in command_permutations(rest) {
        let permutation : Array[@qsm.Command[CSym, RSym]] = [command]
        for item in suffix {
          permutation.push(item)
        }
        result.push(permutation)
      }
    }
    result
  }
}

///|
fn extend_identity_scope(
  scope : Map[@qsm.Var, @qsm.Var],
  vars : Array[@qsm.Var],
) -> Map[@qsm.Var, @qsm.Var] {
  let next = scope.copy()
  for variable in vars {
    next[variable] = variable
  }
  next
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] commands_are_parallel_safe(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  model_after_prefix : MSym,
  prefix_scope : Map[@qsm.Var, @qsm.Var],
  chunk : Array[@qsm.Command[CSym, RSym]],
) -> Bool {
  for command in chunk {
    if (spec.remap_command)(command.command, prefix_scope) is None {
      return false
    }
  }
  for permutation in command_permutations(chunk) {
    let accepted = for index = 0, model = model_after_prefix, gen_sym = @qsm.GenSym::new(); index <
                      permutation.length(); {
      let command = permutation[index]
      let precondition = (spec.precondition)(model, command.command)
      if !precondition.eval() {
        break false
      }
      let (mock_response, next_gen_sym) = (spec.mock)(
        model,
        command.command,
        gen_sym,
      )
      if (spec.response_vars)(mock_response).length() != command.vars.length() {
        break false
      }
      let next_model = (spec.transition_symbolic)(
        model,
        command.command,
        command.response,
      )
      continue index + 1, next_model, next_gen_sym
    } nobreak {
      true
    }
    if !accepted {
      return false
    }
  }
  true
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] split_parallel_commands_after_generation_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : @qsm.Commands[CSym, RSym],
) -> @qsm.ParallelCommands[CSym, RSym] {
  let len = commands.length()
  let prefix_len = len / 2
  let prefix = take_commands(commands, 0, prefix_len)
  let (model_after_prefix, prefix_scope) = for index = 0, model = (spec.init_symbolic_model)(), scope = Map([],
                                                 ); index <
                                              prefix.commands.length(); {
    let command = prefix.commands[index]
    let next_model = (spec.transition_symbolic)(
      model,
      command.command,
      command.response,
    )
    continue index + 1, next_model, extend_identity_scope(scope, command.vars)
  } nobreak {
    (model, scope)
  }
  let chunk : Array[@qsm.Command[CSym, RSym]] = []
  let limit = if len - prefix_len < max_parallel_operations() {
    len
  } else {
    prefix_len + max_parallel_operations()
  }
  for index = prefix_len; index < limit; index = index + 1 {
    let candidate = chunk.copy()
    candidate.push(commands.commands[index])
    if commands_are_parallel_safe(
        spec, model_after_prefix, prefix_scope, candidate,
      ) {
      chunk.push(commands.commands[index])
    } else {
      break
    }
  }
  let left_len = chunk.length() / 2
  let left = commands_from_array(chunk[:left_len].to_owned())
  let right = commands_from_array(chunk[left_len:].to_owned())
  @qsm.ParallelCommands::{ prefix, left, right, }
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] generate_parallel_commands_async_spec(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config~ : @qsm.RunConfig = @qsm.RunConfig::default(),
  seed~ : UInt64 = config.seed,
) -> Result[
  @qsm.ParallelCommands[CSym, RSym],
  @qsm.GenerationFailure[MSym, CSym, RSym],
] {
  match generate_commands_with_seed_async_spec(spec, config~, seed~) {
    Err(failure) => Err(failure)
    Ok(commands) =>
      Ok(split_parallel_commands_after_generation_async(spec, commands))
  }
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon] invalid_config_failure(
  parallel_commands : @qsm.ParallelCommands[CSym, RSym]?,
  message : String,
) -> AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  wrap_replay_failure(parallel_commands, @qsm.InvalidConfig(message))
}

///|
priv struct AsyncReplayState[MCon, V, CCon, RCon] {
  model : MCon
  environment : @qsm.Environment[V]
  history : @qsm.History[CCon, RCon]
  labels : Array[String]
}

///|
priv struct AsyncReplayFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  failure : @qsm.RunFailure[MSym, MCon, CSym, CCon, RSym, RCon]
  cleanup_model : MCon
}

///|
async fn[MCon, S] async_cleanup_after_failure(
  cleanup : async (MCon, S) -> Unit,
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
async fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_prefix_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  prefix : @qsm.Commands[CSym, RSym],
  all_commands : @qsm.Commands[CSym, RSym],
  system : S,
) -> Result[
  AsyncReplayState[MCon, V, CCon, RCon],
  AsyncReplayFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  let initial_history : @qsm.History[CCon, RCon] = @qsm.History::empty()
  let labels : Array[String] = []
  for step_index = 0, model = (spec.init_concrete_model)(), environment = @qsm.Environment::empty(), history = initial_history; step_index <
     prefix.commands.length(); {
    let symbolic = prefix.commands[step_index]
    match (spec.reify_command)(symbolic.command, environment) {
      Err(error) =>
        break Err({
          failure: @qsm.ReifyFailed(
            step_index~,
            symbolic_command=symbolic.command,
            error~,
            commands=all_commands,
            history~,
            shrinks=0,
            shrink_rounds=0,
          ),
          cleanup_model: model,
        })
      Ok(concrete_command) => {
        let pid = @qsm.Pid::{ id: step_index, }
        let invoked = history.push(
          @qsm.Invocation(pid~, command=concrete_command),
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
            let failed_history = invoked.push(@qsm.Exception(pid~, message~))
            break Err({
              failure: @qsm.ExecutionFailed(
                step_index~,
                command=concrete_command,
                symbolic_command=symbolic.command,
                model~,
                commands=all_commands,
                history=failed_history,
                message~,
                shrinks=0,
                shrink_rounds=0,
              ),
              cleanup_model: model,
            })
          }
          Ok(concrete_response) => {
            let responded = invoked.push(
              @qsm.Response(pid~, response=concrete_response),
            )
            let next_model = (spec.transition_concrete)(
              model, concrete_command, concrete_response,
            )
            let postcondition = (spec.postcondition)(
              model, concrete_command, concrete_response,
            )
            if !postcondition.eval() {
              break Err({
                failure: @qsm.PostconditionFailed(
                  step_index~,
                  command=concrete_command,
                  symbolic_command=symbolic.command,
                  response=concrete_response,
                  model~,
                  next_model~,
                  logic=postcondition,
                  commands=all_commands,
                  history=responded,
                  shrinks=0,
                  shrink_rounds=0,
                ),
                cleanup_model: model,
              })
            }
            match
              (spec.bind_response)(
                symbolic.response,
                concrete_response,
                environment,
              ) {
              Err(error) =>
                break Err({
                  failure: @qsm.BindFailed(
                    step_index~,
                    symbolic_response=symbolic.response,
                    response=concrete_response,
                    error~,
                    commands=all_commands,
                    history=responded,
                    shrinks=0,
                    shrink_rounds=0,
                  ),
                  cleanup_model: model,
                })
              Ok(next_environment) => {
                let invariant = (spec.invariant)(next_model)
                if !invariant.eval() {
                  break Err({
                    failure: @qsm.InvariantBroken(
                      step_index~,
                      model=next_model,
                      logic=invariant,
                      commands=all_commands,
                      history=responded,
                      shrinks=0,
                      shrink_rounds=0,
                    ),
                    cleanup_model: next_model,
                  })
                }
                for
                  label in (spec.label)(
                    model, concrete_command, concrete_response,
                  ) {
                  labels.push(label)
                }
                continue step_index + 1, next_model, next_environment, responded
              }
            }
          }
        }
      }
    }
  } nobreak {
    Ok({ model, environment, history, labels, })
  }
}

///|
priv enum BranchFailure[CSym, CCon, RSym, RCon] {
  BranchReifyFailed(
    local_index~ : Int32,
    symbolic_command~ : CSym,
    error~ : @qsm.EnvError
  )
  BranchExecutionFailed(
    local_index~ : Int32,
    command~ : CCon,
    symbolic_command~ : CSym,
    message~ : String
  )
  BranchBindFailed(
    local_index~ : Int32,
    symbolic_response~ : RSym,
    response~ : RCon,
    error~ : @qsm.BindError
  )
}

///|
async fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_branch_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  branch : @qsm.Commands[CSym, RSym],
  base_environment : @qsm.Environment[V],
  system : S,
  pid_base : Int32,
  concurrent_events : Array[@qsm.HistoryEvent[CCon, RCon]],
) -> Result[@qsm.Environment[V], BranchFailure[CSym, CCon, RSym, RCon]] {
  for local_index = 0, environment = copy_environment(base_environment); local_index <
     branch.commands.length(); {
    let symbolic = branch.commands[local_index]
    match (spec.reify_command)(symbolic.command, environment) {
      Err(error) =>
        break Err(
          BranchReifyFailed(
            local_index~,
            symbolic_command=symbolic.command,
            error~,
          ),
        )
      Ok(concrete_command) => {
        let pid = @qsm.Pid::{ id: pid_base + local_index, }
        concurrent_events.push(@qsm.Invocation(pid~, command=concrete_command))
        let run_result = try
          (spec.run_command)(concrete_command, system)
        catch {
          error => Err(error_message(error))
        } noraise {
          response => Ok(response)
        }
        match run_result {
          Err(message) => {
            concurrent_events.push(@qsm.Exception(pid~, message~))
            break Err(
              BranchExecutionFailed(
                local_index~,
                command=concrete_command,
                symbolic_command=symbolic.command,
                message~,
              ),
            )
          }
          Ok(concrete_response) => {
            concurrent_events.push(
              @qsm.Response(pid~, response=concrete_response),
            )
            match
              (spec.bind_response)(
                symbolic.response,
                concrete_response,
                environment,
              ) {
              Err(error) =>
                break Err(
                  BranchBindFailed(
                    local_index~,
                    symbolic_response=symbolic.response,
                    response=concrete_response,
                    error~,
                  ),
                )
              Ok(next_environment) => continue local_index + 1, next_environment
            }
          }
        }
      }
    }
  } nobreak {
    Ok(environment)
  }
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon] branch_failure_to_run_failure(
  failure : BranchFailure[CSym, CCon, RSym, RCon],
  step_base : Int32,
  model_after_prefix : MCon,
  all_commands : @qsm.Commands[CSym, RSym],
  history : @qsm.History[CCon, RCon],
) -> @qsm.RunFailure[MSym, MCon, CSym, CCon, RSym, RCon] {
  match failure {
    BranchReifyFailed(local_index~, symbolic_command~, error~) =>
      @qsm.ReifyFailed(
        step_index=step_base + local_index,
        symbolic_command~,
        error~,
        commands=all_commands,
        history~,
        shrinks=0,
        shrink_rounds=0,
      )
    BranchExecutionFailed(local_index~, command~, symbolic_command~, message~) =>
      @qsm.ExecutionFailed(
        step_index=step_base + local_index,
        command~,
        symbolic_command~,
        model=model_after_prefix,
        commands=all_commands,
        history~,
        message~,
        shrinks=0,
        shrink_rounds=0,
      )
    BranchBindFailed(local_index~, symbolic_response~, response~, error~) =>
      @qsm.BindFailed(
        step_index=step_base + local_index,
        symbolic_response~,
        response~,
        error~,
        commands=all_commands,
        history~,
        shrinks=0,
        shrink_rounds=0,
      )
  }
}

///|
priv enum LineariseOutcome[MCon] {
  Linearised(model~ : MCon, labels~ : Array[String])
  NotLinearizable(logic~ : @qsm.Logic)
  BudgetExceeded(operation_count~ : Int32, max_operations~ : Int32)
}

///|
fn[C, R] count_invocations(events : Array[@qsm.HistoryEvent[C, R]]) -> Int32 {
  let mut count = 0
  for event in events {
    if event is @qsm.Invocation(..) {
      count += 1
    }
  }
  count
}

///|
fn[C, R] opening_invocation_count(
  events : Array[@qsm.HistoryEvent[C, R]],
) -> Int32 {
  for index = 0; index < events.length(); index = index + 1 {
    match events[index] {
      @qsm.Invocation(..) => ()
      _ => break index
    }
  } nobreak {
    events.length()
  }
}

///|
fn[C, R] find_matching_response(
  events : Array[@qsm.HistoryEvent[C, R]],
  start : Int32,
  pid : @qsm.Pid,
) -> (Int32, R)? {
  for index in (start + 1)..<events.length() {
    match events[index] {
      @qsm.Response(pid=response_pid, response~) =>
        if response_pid == pid {
          return Some((index, response))
        }
      _ => ()
    }
  }
  None
}

///|
fn[C, R] remove_event_pair(
  events : Array[@qsm.HistoryEvent[C, R]],
  first : Int32,
  second : Int32,
) -> Array[@qsm.HistoryEvent[C, R]] {
  let remaining : Array[@qsm.HistoryEvent[C, R]] = []
  for index, event in events {
    if index != first && index != second {
      remaining.push(event)
    }
  }
  remaining
}

///|
fn merge_failure_logics(logics : Array[@qsm.Logic]) -> @qsm.Logic {
  for index = 0, merged = @qsm.Logic::predicate(
          name="no valid linearization",
          value=false,
        ); index < logics.length(); {
    continue index + 1, @qsm.logic_and(merged, logics[index])
  } nobreak {
    merged
  }
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] linearise_dfs(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  model : MCon,
  events : Array[@qsm.HistoryEvent[CCon, RCon]],
  labels : Array[String],
) -> Result[(MCon, Array[String]), Array[@qsm.Logic]] {
  if events.length() == 0 {
    return Ok((model, labels))
  }
  let candidate_count = opening_invocation_count(events)
  let failures : Array[@qsm.Logic] = []
  if candidate_count == 0 {
    failures.push(
      @qsm.Logic::predicate(
        name="no invocation available before next terminal event",
        value=false,
      ),
    )
  }
  for candidate_index in 0..<candidate_count {
    match events[candidate_index] {
      @qsm.Invocation(pid~, command~) =>
        match find_matching_response(events, candidate_index, pid) {
          None =>
            failures.push(
              @qsm.Logic::predicate(
                name="candidate response is missing",
                value=false,
              ).annotate("pid \{pid.id}"),
            )
          Some((response_index, response)) => {
            let postcondition = (spec.postcondition)(model, command, response)
            if !postcondition.eval() {
              failures.push(
                postcondition.annotate(
                  "candidate pid \{pid.id} postcondition failed",
                ),
              )
            } else {
              let next_model = (spec.transition_concrete)(
                model, command, response,
              )
              let invariant = (spec.invariant)(next_model)
              if !invariant.eval() {
                failures.push(
                  invariant.annotate("candidate pid \{pid.id} invariant failed"),
                )
              } else {
                let next_events = remove_event_pair(
                  events, candidate_index, response_index,
                )
                let next_labels = labels.copy()
                for label in (spec.label)(model, command, response) {
                  next_labels.push(label)
                }
                match
                  linearise_dfs(spec, next_model, next_events, next_labels) {
                  Ok(success) => return Ok(success)
                  Err(child_failures) =>
                    for child_failure in child_failures {
                      failures.push(child_failure)
                    }
                }
              }
            }
          }
        }
      _ => ()
    }
  }
  Err(failures)
}

///|
fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] linearise_history(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  start_model : MCon,
  history : @qsm.History[CCon, RCon],
  max_operations : Int32,
) -> LineariseOutcome[MCon] {
  let operation_count = count_invocations(history.events)
  if operation_count > max_operations {
    BudgetExceeded(operation_count~, max_operations~)
  } else {
    match linearise_dfs(spec, start_model, history.events.copy(), []) {
      Ok((model, labels)) => Linearised(model~, labels~)
      Err(failures) => {
        let logic = merge_failure_logics(failures).annotate(
          "remaining events: \{history.events.length()}",
        )
        NotLinearizable(logic~)
      }
    }
  }
}

///|
pub async fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] run_parallel_commands_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  commands : @qsm.ParallelCommands[CSym, RSym],
  config~ : @qsm.RunConfig = @qsm.RunConfig::default(),
) -> Result[
  @qsm.RunReport[CSym, RSym, CCon, RCon],
  AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match validate_generation_config(config) {
    Some(message) => Err(invalid_config_failure(Some(commands), message))
    None => {
      let all_commands = flatten_parallel_commands(commands)
      let operation_count = commands.left.length() + commands.right.length()
      let max_operations = max_parallel_operations()
      if operation_count > max_operations {
        return Err(
          LinearizationBudgetExceeded(
            parallel_commands=commands,
            commands=all_commands,
            history=@qsm.History::empty(),
            operation_count~,
            max_operations~,
            shrinks=0,
            shrink_rounds=0,
          ),
        )
      }
      let system_result = try (spec.init_system)() catch {
        error => Err(error_message(error))
      } noraise {
        system => Ok(system)
      }
      match system_result {
        Err(message) =>
          Err(
            wrap_replay_failure(
              Some(commands),
              @qsm.InitFailed(
                commands=all_commands,
                message~,
                shrinks=0,
                shrink_rounds=0,
              ),
            ),
          )
        Ok(system) =>
          match run_prefix_async(spec, commands.prefix, all_commands, system) {
            Err(prefix_failure) => {
              async_cleanup_after_failure(
                spec.cleanup,
                prefix_failure.cleanup_model,
                system,
              )
              Err(wrap_replay_failure(Some(commands), prefix_failure.failure))
            }
            Ok(prefix_state) => {
              let concurrent_events : Array[@qsm.HistoryEvent[CCon, RCon]] = []
              let left_base = commands.prefix.length()
              let right_base = left_base + commands.left.length()
              let (left_result, right_result) = @async.with_task_group(group => {
                let left_task = group.spawn(() => {
                  run_branch_async(
                    spec,
                    commands.left,
                    prefix_state.environment,
                    system,
                    left_base,
                    concurrent_events,
                  )
                })
                let right_task = group.spawn(() => {
                  run_branch_async(
                    spec,
                    commands.right,
                    prefix_state.environment,
                    system,
                    right_base,
                    concurrent_events,
                  )
                })
                (left_task.wait(), right_task.wait())
              })
              let full_history = append_history_events(
                prefix_state.history,
                concurrent_events,
              )
              match (left_result, right_result) {
                (Err(failure), _) => {
                  async_cleanup_after_failure(
                    spec.cleanup,
                    prefix_state.model,
                    system,
                  )
                  Err(
                    wrap_replay_failure(
                      Some(commands),
                      branch_failure_to_run_failure(
                        failure,
                        left_base,
                        prefix_state.model,
                        all_commands,
                        full_history,
                      ),
                    ),
                  )
                }
                (_, Err(failure)) => {
                  async_cleanup_after_failure(
                    spec.cleanup,
                    prefix_state.model,
                    system,
                  )
                  Err(
                    wrap_replay_failure(
                      Some(commands),
                      branch_failure_to_run_failure(
                        failure,
                        right_base,
                        prefix_state.model,
                        all_commands,
                        full_history,
                      ),
                    ),
                  )
                }
                (Ok(left_environment), Ok(right_environment)) => {
                  let left_delta = environment_delta(
                    prefix_state.environment,
                    left_environment,
                  )
                  let right_delta = environment_delta(
                    prefix_state.environment,
                    right_environment,
                  )
                  match prefix_state.environment.merge(left_delta) {
                    Err(error) => {
                      async_cleanup_after_failure(
                        spec.cleanup,
                        prefix_state.model,
                        system,
                      )
                      let logic = @qsm.Logic::predicate(
                        name="parallel branch environments are disjoint",
                        value=false,
                      ).annotate(@debug.to_string(error))
                      Err(
                        BranchEnvironmentMergeFailed(
                          parallel_commands=commands,
                          commands=all_commands,
                          history=full_history,
                          error~,
                          logic~,
                          shrinks=0,
                          shrink_rounds=0,
                        ),
                      )
                    }
                    Ok(left_merged) =>
                      match left_merged.merge(right_delta) {
                        Err(error) => {
                          async_cleanup_after_failure(
                            spec.cleanup,
                            prefix_state.model,
                            system,
                          )
                          let logic = @qsm.Logic::predicate(
                            name="parallel branch environments are disjoint",
                            value=false,
                          ).annotate(@debug.to_string(error))
                          Err(
                            BranchEnvironmentMergeFailed(
                              parallel_commands=commands,
                              commands=all_commands,
                              history=full_history,
                              error~,
                              logic~,
                              shrinks=0,
                              shrink_rounds=0,
                            ),
                          )
                        }
                        Ok(_) => {
                          let concurrent_history = history_from_events(
                            concurrent_events,
                          )
                          match
                            linearise_history(
                              spec,
                              prefix_state.model,
                              concurrent_history,
                              max_operations,
                            ) {
                            BudgetExceeded(operation_count~, max_operations~) => {
                              async_cleanup_after_failure(
                                spec.cleanup,
                                prefix_state.model,
                                system,
                              )
                              Err(
                                LinearizationBudgetExceeded(
                                  parallel_commands=commands,
                                  commands=all_commands,
                                  history=full_history,
                                  operation_count~,
                                  max_operations~,
                                  shrinks=0,
                                  shrink_rounds=0,
                                ),
                              )
                            }
                            NotLinearizable(logic~) => {
                              async_cleanup_after_failure(
                                spec.cleanup,
                                prefix_state.model,
                                system,
                              )
                              Err(
                                LinearizationFailed(
                                  parallel_commands=commands,
                                  commands=all_commands,
                                  history=full_history,
                                  logic~,
                                  shrinks=0,
                                  shrink_rounds=0,
                                ),
                              )
                            }
                            Linearised(
                              model=final_model,
                              labels=parallel_labels
                            ) => {
                              let cleanup_result = try
                                (spec.cleanup)(final_model, system)
                              catch {
                                error => Err(error_message(error))
                              } noraise {
                                _ => Ok(())
                              }
                              match cleanup_result {
                                Err(message) =>
                                  Err(
                                    wrap_replay_failure(
                                      Some(commands),
                                      @qsm.CleanupFailed(
                                        commands=all_commands,
                                        history=full_history,
                                        message~,
                                        shrinks=0,
                                        shrink_rounds=0,
                                      ),
                                    ),
                                  )
                                Ok(_) => {
                                  let labels = prefix_state.labels.copy()
                                  for label in parallel_labels {
                                    labels.push(label)
                                  }
                                  let unique_labels = @qsm.collect_labels(
                                    labels,
                                  )
                                  let distribution = @qsm.command_names(
                                    all_commands,
                                    spec.command_name,
                                  )
                                  let missing_labels = missing_required_values(
                                    config.required_labels,
                                    unique_labels,
                                  )
                                  let missing_command_names = @qsm.cover_command_names(
                                    distribution,
                                    config.required_command_names,
                                  )
                                  if missing_labels.length() > 0 ||
                                    missing_command_names.length() > 0 {
                                    Err(
                                      wrap_replay_failure(
                                        Some(commands),
                                        @qsm.CoverageFailed(
                                          commands=all_commands,
                                          history=full_history,
                                          missing_labels~,
                                          missing_command_names~,
                                          shrinks=0,
                                          shrink_rounds=0,
                                        ),
                                      ),
                                    )
                                  } else {
                                    Ok(@qsm.RunReport::{
                                      seed: config.seed,
                                      cases_run: 1,
                                      commands_run: all_commands.length(),
                                      commands: all_commands,
                                      history: full_history,
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
              }
            }
          }
      }
    }
  }
}

///|
pub async fn[MSym, MCon, CSym, CCon, RSym, RCon, V, S] check_parallel_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config~ : @qsm.RunConfig = @qsm.RunConfig::default(),
) -> Result[
  @qsm.RunReport[CSym, RSym, CCon, RCon],
  AsyncRunFailure[MSym, MCon, CSym, CCon, RSym, RCon],
] {
  match validate_generation_config(config) {
    Some(message) => Err(invalid_config_failure(None, message))
    None =>
      for case_index = 0, commands_run = 0, last_report = None; case_index <
         config.cases; {
        let case_seed = config.seed + case_index.to_uint64()
        match
          generate_parallel_commands_async_spec(spec, config~, seed=case_seed) {
          Err(failure) =>
            break Err(
              wrap_replay_failure(
                None,
                @qsm.GenerationFailed(failure~, shrinks=0, shrink_rounds=0),
              ),
            )
          Ok(parallel_commands) =>
            match
              run_parallel_commands_async(spec, parallel_commands, config~) {
              Ok(report) =>
                continue case_index + 1,
                  commands_run + report.commands_run,
                  Some(report)
              Err(failure) => break Err(failure)
            }
        }
      } nobreak {
        match last_report {
          Some(report) =>
            Ok(@qsm.RunReport::{
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
            Ok(@qsm.RunReport::{
              seed: config.seed,
              cases_run: config.cases,
              commands_run,
              commands: @qsm.Commands::empty(),
              history: @qsm.History::empty(),
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
pub async fn[
  MSym : @debug.Debug,
  MCon : @debug.Debug,
  CSym : @debug.Debug,
  CCon : @debug.Debug,
  RSym : @debug.Debug,
  RCon : @debug.Debug,
  V,
  S,
] assert_check_parallel_async(
  spec : AsyncStateMachine[MSym, MCon, CSym, CCon, RSym, RCon, V, S],
  config~ : @qsm.RunConfig = @qsm.RunConfig::default(),
) -> @qsm.RunReport[CSym, RSym, CCon, RCon] {
  match check_parallel_async(spec, config~) {
    Ok(report) => report
    Err(failure) =>
      fail("state machine parallel check failed: \{@debug.to_string(failure)}")
  }
}
