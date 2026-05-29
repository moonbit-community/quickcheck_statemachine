///|
/// Errors raised while reifying symbolic commands into concrete commands.
pub(all) enum EnvError {
  // A command mentioned a symbolic variable that was never produced by a prior
  // response, or was removed during shrinking.
  MissingVar(Var)
  // Two command streams attempted to bind the same symbolic variable while
  // merging environments.
  DuplicateVar(Var)
} derive(Eq, Debug)

///|
/// Errors raised while binding a real response back into the execution
/// environment.
pub(all) enum BindError {
  // User-defined binding failure, for example when response shapes do not match.
  BindMessage(String)
  // The symbolic response predicted a different number of freshly created
  // variables than the concrete response can provide.
  BindVarCountMismatch(expected~ : Int, actual~ : Int)
} derive(Eq, Debug)

///|
/// Runtime map from symbolic variables to concrete values.
///
/// During generation, commands only carry `Var`s. During replay, each concrete
/// response can extend this environment; later commands call `reify_command` to
/// look up the concrete values corresponding to those variables.
pub(all) struct Environment[V] {
  bindings : Map[Var, V]
} derive(Debug)

///|
/// Creates an empty execution environment.
pub fn[V] Environment::empty() -> Environment[V] {
  { bindings: Map([]) }
}

///|
/// Returns a copy of the environment with one additional binding.
///
/// This helper is intentionally permissive and overwrites an existing binding.
/// Use `merge` when duplicate detection is part of the operation contract.
pub fn[V] Environment::insert(
  self : Environment[V],
  variable : Var,
  value : V,
) -> Environment[V] {
  let bindings = self.bindings.copy()
  bindings[variable] = value
  { bindings, }
}

///|
/// Looks up a concrete value or reports a state-machine reification error.
pub fn[V] Environment::lookup(
  self : Environment[V],
  variable : Var,
) -> Result[V, EnvError] {
  match self.bindings.get(variable) {
    Some(value) => Ok(value)
    None => Err(MissingVar(variable))
  }
}

///|
/// Looks up a concrete value without constructing an `EnvError`.
pub fn[V] Environment::get(self : Environment[V], variable : Var) -> V? {
  self.bindings.get(variable)
}

///|
/// Checks whether a symbolic variable is already bound.
pub fn[V] Environment::contains(self : Environment[V], variable : Var) -> Bool {
  self.bindings.contains(variable)
}

///|
/// Combines two environments when their symbolic-variable domains are disjoint.
///
/// This is useful for future parallel checking, where independent command
/// branches may produce bindings that must be joined before a later command can
/// be reified.
pub fn[V] Environment::merge(
  self : Environment[V],
  other : Environment[V],
) -> Result[Environment[V], EnvError] {
  let bindings = self.bindings.copy()
  for variable, value in other.bindings {
    if bindings.contains(variable) {
      return Err(DuplicateVar(variable))
    }
    bindings[variable] = value
  }
  Ok({ bindings, })
}

///|
/// Returns the number of symbolic variables with concrete bindings.
pub fn[V] Environment::length(self : Environment[V]) -> Int {
  self.bindings.length()
}
