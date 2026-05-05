///|
// Minimal dependency model for shrinking:
// `ShrinkNew` produces a symbolic reference and `ShrinkUse` consumes it. This
// mirrors the file-handle dependency from the blogs without file-system noise,
// making the property focused on whether the shrinker rejects candidates with
// dangling symbolic references.
enum ShrinkCommand {
  ShrinkNew
  ShrinkUse(@quickcheck_statemachine.Ref[Int])
} derive(Eq, Debug)

///|
enum ShrinkConcreteCommand {
  ShrinkConcreteNew
  ShrinkConcreteUse(Int)
} derive(Eq, Debug)

///|
enum ShrinkResponse {
  ShrinkNewed(@quickcheck_statemachine.Var)
  ShrinkUsed
} derive(Eq, Debug)

///|
enum ShrinkConcreteResponse {
  ShrinkConcreteNewed(Int)
  ShrinkConcreteUsed
} derive(Eq, Debug)

///|
fn shrink_ref_known(
  model : Array[@quickcheck_statemachine.Var],
  handle : @quickcheck_statemachine.Var,
) -> Bool {
  for item in model {
    if item == handle {
      return true
    }
  }
  false
}

///|
fn shrink_spec() -> @quickcheck_statemachine.StateMachine[
  Array[@quickcheck_statemachine.Var],
  Int,
  ShrinkCommand,
  ShrinkConcreteCommand,
  ShrinkResponse,
  ShrinkConcreteResponse,
  Int,
  Unit,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => [],
    init_concrete_model=() => 0,
    init_system=() => (),
    generator=(model, size, rng) => {
      ignore(model)
      ignore(size)
      ignore(rng)
      None
    },
    mock=(model, command, gen_sym) => {
      ignore(model)
      match command {
        ShrinkNew => {
          let (handle, next) = gen_sym.fresh()
          (ShrinkNewed(handle), next)
        }
        ShrinkUse(_) => (ShrinkUsed, gen_sym)
      }
    },
    response_vars=response => {
      match response {
        ShrinkNewed(handle) => [handle]
        ShrinkUsed => []
      }
    },
    transition_symbolic=(model, command, response) => {
      ignore(command)
      match response {
        ShrinkNewed(handle) => {
          let next = model.copy()
          next.push(handle)
          next
        }
        ShrinkUsed => model
      }
    },
    transition_concrete=(model, command, response) => {
      ignore(command)
      ignore(response)
      model
    },
    precondition=(model, command) => {
      let ok = match command {
        ShrinkNew => true
        ShrinkUse(@quickcheck_statemachine.Ref::Symbolic(handle)) =>
          shrink_ref_known(model, handle)
        ShrinkUse(@quickcheck_statemachine.Ref::Concrete(_)) => true
      }
      @quickcheck_statemachine.Logic::boolean(ok)
    },
    remap_command=(command, scope) => {
      match command {
        ShrinkNew => Some(ShrinkNew)
        ShrinkUse(@quickcheck_statemachine.Ref::Symbolic(handle)) =>
          match scope.get(handle) {
            Some(next) =>
              Some(ShrinkUse(@quickcheck_statemachine.Ref::Symbolic(next)))
            None => None
          }
        ShrinkUse(@quickcheck_statemachine.Ref::Concrete(value)) =>
          Some(ShrinkUse(@quickcheck_statemachine.Ref::Concrete(value)))
      }
    },
    reify_command=(command, environment) => {
      match command {
        ShrinkNew => Ok(ShrinkConcreteNew)
        ShrinkUse(@quickcheck_statemachine.Ref::Concrete(value)) =>
          Ok(ShrinkConcreteUse(value))
        ShrinkUse(@quickcheck_statemachine.Ref::Symbolic(handle)) =>
          match environment.lookup(handle) {
            Ok(value) => Ok(ShrinkConcreteUse(value))
            Err(error) => Err(error)
          }
      }
    },
    run_command=(command, system) => {
      ignore(system)
      match command {
        ShrinkConcreteNew => ShrinkConcreteNewed(0)
        ShrinkConcreteUse(_) => ShrinkConcreteUsed
      }
    },
    bind_response=(symbolic, concrete, environment) => {
      match (symbolic, concrete) {
        (ShrinkNewed(handle), ShrinkConcreteNewed(value)) =>
          Ok(environment.insert(handle, value))
        _ => Ok(environment)
      }
    },
  )
}

///|
// Dependency-aware shrink regression:
// Removing the producer command would leave `ShrinkUse(Var 0)` without a
// binding. The property checks that the shrinker either keeps the producer or
// rejects the candidate, which is the essential "remove dependent commands
// together" behavior required for stateful programs.
test "shrinking rejects candidates with dangling symbolic refs" {
  let v0 = @quickcheck_statemachine.Var::{ id: 0 }
  let commands = @quickcheck_statemachine.Commands::{
    commands: [
      @quickcheck_statemachine.Command::{
        command: ShrinkNew,
        response: ShrinkNewed(v0),
        vars: [v0],
      },
      @quickcheck_statemachine.Command::{
        command: ShrinkUse(@quickcheck_statemachine.Ref::Symbolic(v0)),
        response: ShrinkUsed,
        vars: [],
      },
    ],
  }
  let candidates = @quickcheck_statemachine.shrink_commands_once(
    shrink_spec(),
    commands,
  )
  for candidate in candidates {
    if candidate.length() == 1 {
      assert_true(candidate.commands[0].command is ShrinkNew)
    }
  }
}
