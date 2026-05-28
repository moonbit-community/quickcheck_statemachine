///|
pub(all) enum EnvError {
  MissingVar(Var)
  DuplicateVar(Var)
} derive(Eq, Debug)

///|
pub(all) enum BindError {
  BindMessage(String)
  BindVarCountMismatch(expected~ : Int, actual~ : Int)
} derive(Eq, Debug)

///|
pub(all) struct Environment[V] {
  bindings : Map[Var, V]
} derive(Debug)

///|
pub fn[V] Environment::empty() -> Environment[V] {
  { bindings: Map([]) }
}

///|
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
pub fn[V] Environment::get(self : Environment[V], variable : Var) -> V? {
  self.bindings.get(variable)
}

///|
pub fn[V] Environment::contains(self : Environment[V], variable : Var) -> Bool {
  self.bindings.contains(variable)
}

///|
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
pub fn[V] Environment::length(self : Environment[V]) -> Int {
  self.bindings.length()
}
