///|
pub(all) struct Var {
  id : Int
} derive(Eq, Hash, Debug)

///|
pub fn Var::to_string(self : Var) -> String {
  "v\{self.id}"
}

///|
pub(all) enum Ref[V] {
  Symbolic(Var)
  Concrete(V)
} derive(Eq, Debug)

///|
pub(all) struct GenSym {
  mut next : Int
} derive(Eq, Debug)

///|
pub fn GenSym::new() -> GenSym {
  { next: 0 }
}

///|
pub fn GenSym::fresh(self : GenSym) -> (Var, GenSym) {
  let fresh_var = Var::{ id: self.next }
  self.next = self.next + 1
  (fresh_var, self)
}
