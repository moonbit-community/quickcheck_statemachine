// ref: https://stevana.github.io/the_sad_state_of_property-based_testing_libraries.html

///|
// Queue model and property:
// `QueueState` is the pure fake used as the specification. It stores each queue
// as a normal FIFO array plus a fixed capacity; `QueueSystem` is the mutable
// circular-buffer implementation.
struct QueueId {
  id : Int
} derive(Eq, Debug)

///|
struct QueueModel {
  reference : @quickcheck_statemachine.Ref[QueueId]
  elems : Array[Int]
  capacity : Int
} derive(Eq, Debug)

///|
struct QueueState {
  queues : Array[QueueModel]
} derive(Eq, Debug)

///|
enum QueueCommand {
  QueueNew(Int)
  QueuePut(@quickcheck_statemachine.Ref[QueueId], Int)
  QueueGet(@quickcheck_statemachine.Ref[QueueId])
  QueueSize(@quickcheck_statemachine.Ref[QueueId])
} derive(Eq, Debug)

///|
enum QueueResponse {
  QueueNewed(@quickcheck_statemachine.Ref[QueueId])
  QueuePutDone
  QueueGot(Int)
  QueueSized(Int)
} derive(Eq, Debug)

///|
enum QueueBug {
  QueueNoBug
  QueueCapacityBug
  QueueRawSizeBug
  QueueAbsSizeBug
} derive(Eq, Debug)

///|
struct CircularQueue {
  slots : Array[Int]
  mut input : Int
  mut output : Int
  bug : QueueBug
} derive(Eq, Debug)

///|
struct QueueSystem {
  queues : Array[CircularQueue]
} derive(Eq, Debug)

///|
fn int_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn CircularQueue::new(capacity : Int, bug : QueueBug) -> CircularQueue {
  let storage_size = match bug {
    QueueCapacityBug => capacity
    QueueNoBug | QueueRawSizeBug | QueueAbsSizeBug => capacity + 1
  }
  let slots : Array[Int] = []
  for _ in 0..<storage_size {
    slots.push(0)
  }
  { slots, input: 0, output: 0, bug }
}

///|
fn CircularQueue::put(self : CircularQueue, item : Int) -> Unit {
  self.slots[self.input] = item
  self.input = (self.input + 1) % self.slots.length()
}

///|
fn CircularQueue::get(self : CircularQueue) -> Int {
  let item = self.slots[self.output]
  self.output = (self.output + 1) % self.slots.length()
  item
}

///|
fn CircularQueue::size(self : CircularQueue) -> Int {
  match self.bug {
    QueueRawSizeBug => (self.input - self.output) % self.slots.length()
    QueueAbsSizeBug => int_abs(self.input - self.output) % self.slots.length()
    QueueNoBug | QueueCapacityBug =>
      (self.input - self.output + self.slots.length()) % self.slots.length()
  }
}

///|
fn queue_index(
  model : QueueState,
  reference : @quickcheck_statemachine.Ref[QueueId],
) -> Int? {
  for index = 0; index < model.queues.length(); {
    if model.queues[index].reference == reference {
      return Some(index)
    }
    continue index + 1
  }
  None
}

///|
fn queue_exists(
  model : QueueState,
  reference : @quickcheck_statemachine.Ref[QueueId],
) -> Bool {
  queue_index(model, reference) is Some(_)
}

///|
// The precondition is the client contract for valid queue operations: users may
// create positive-capacity queues, put only while not full, get only while not
// empty, and query only existing queues. When the generator repeatedly proposes
// a full `put`, generation should deadlock instead of executing an invalid
// command against either implementation.
fn queue_precondition(
  model : QueueState,
  command : QueueCommand,
) -> @quickcheck_statemachine.Logic {
  let ok = match command {
    QueueNew(capacity) => capacity > 0
    QueuePut(reference, _) =>
      match queue_index(model, reference) {
        Some(index) =>
          model.queues[index].elems.length() < model.queues[index].capacity
        None => false
      }
    QueueGet(reference) =>
      match queue_index(model, reference) {
        Some(index) => model.queues[index].elems.length() > 0
        None => false
      }
    QueueSize(reference) => queue_exists(model, reference)
  }
  @quickcheck_statemachine.Logic::predicate(name="queue precondition", value=ok)
}

///|
// The first blog run deliberately forgot the "queue is full" precondition. This
// variant keeps that bug available as a regression scenario so the checked-in
// examples can show both the failing fake and the later fixed precondition.
fn queue_precondition_without_full_check(
  model : QueueState,
  command : QueueCommand,
) -> @quickcheck_statemachine.Logic {
  let ok = match command {
    QueueNew(capacity) => capacity > 0
    QueuePut(reference, _) => queue_exists(model, reference)
    QueueGet(reference) =>
      match queue_index(model, reference) {
        Some(index) => model.queues[index].elems.length() > 0
        None => false
      }
    QueueSize(reference) => queue_exists(model, reference)
  }
  @quickcheck_statemachine.Logic::predicate(
    name="queue precondition without full check",
    value=ok,
  )
}

///|
fn array_tail(xs : Array[Int]) -> Array[Int] {
  let tail : Array[Int] = []
  for i in 1..<xs.length() {
    tail.push(xs[i])
  }
  tail
}

///|
fn queue_update(
  model : QueueState,
  index : Int,
  queue : QueueModel,
) -> QueueState {
  let queues = model.queues.copy()
  queues[index] = queue
  { queues, }
}

///|
fn queue_transition(
  model : QueueState,
  command : QueueCommand,
  response : QueueResponse,
) -> QueueState {
  match command {
    QueueNew(capacity) =>
      match response {
        QueueNewed(reference) => {
          let queues = model.queues.copy()
          queues.push({ reference, elems: [], capacity })
          { queues, }
        }
        _ => model
      }
    QueuePut(reference, item) =>
      match queue_index(model, reference) {
        Some(index) => {
          let queue = model.queues[index]
          let elems = queue.elems.copy()
          elems.push(item)
          queue_update(model, index, {
            reference: queue.reference,
            elems,
            capacity: queue.capacity,
          })
        }
        None => model
      }
    QueueGet(reference) =>
      match queue_index(model, reference) {
        Some(index) => {
          let queue = model.queues[index]
          queue_update(model, index, {
            reference: queue.reference,
            elems: array_tail(queue.elems),
            capacity: queue.capacity,
          })
        }
        None => model
      }
    QueueSize(_) => model
  }
}

///|
fn queue_mock(
  model : QueueState,
  command : QueueCommand,
  gen_sym : @quickcheck_statemachine.GenSym,
) -> (QueueResponse, @quickcheck_statemachine.GenSym) {
  match command {
    QueueNew(_) => {
      let (fresh_var, next_gen_sym) = gen_sym.fresh()
      (QueueNewed(Symbolic(fresh_var)), next_gen_sym)
    }
    QueuePut(_, _) => (QueuePutDone, gen_sym)
    QueueGet(reference) =>
      match queue_index(model, reference) {
        Some(index) => (QueueGot(model.queues[index].elems[0]), gen_sym)
        None => (QueueGot(0), gen_sym)
      }
    QueueSize(reference) =>
      match queue_index(model, reference) {
        Some(index) => (QueueSized(model.queues[index].elems.length()), gen_sym)
        None => (QueueSized(0), gen_sym)
      }
  }
}

///|
fn queue_response_vars(
  response : QueueResponse,
) -> Array[@quickcheck_statemachine.Var] {
  match response {
    QueueNewed(Symbolic(fresh_var)) => [fresh_var]
    _ => []
  }
}

///|
fn queue_postcondition(
  model : QueueState,
  command : QueueCommand,
  response : QueueResponse,
) -> @quickcheck_statemachine.Logic {
  let ok = match (command, response) {
    (QueueNew(_), QueueNewed(Concrete(queue_id))) =>
      !queue_exists(model, Concrete(queue_id))
    (QueuePut(_, _), QueuePutDone) => true
    (QueueGet(reference), QueueGot(item)) =>
      match queue_index(model, reference) {
        Some(index) => model.queues[index].elems[0] == item
        None => false
      }
    (QueueSize(reference), QueueSized(size)) =>
      match queue_index(model, reference) {
        Some(index) => model.queues[index].elems.length() == size
        None => false
      }
    _ => false
  }
  @quickcheck_statemachine.Logic::predicate(
    name="queue response matches model",
    value=ok,
  )
}

///|
fn concrete_queue_index(
  reference : @quickcheck_statemachine.Ref[QueueId],
) -> Int raise {
  match reference {
    Concrete(queue_id) => queue_id.id
    Symbolic(fresh_var) => fail("unreified queue reference v\{fresh_var.id}")
  }
}

///|
fn run_queue_command(
  command : QueueCommand,
  system : QueueSystem,
  bug : QueueBug,
) -> QueueResponse raise {
  match command {
    QueueNew(capacity) => {
      let id = QueueId::{ id: system.queues.length() }
      system.queues.push(CircularQueue::new(capacity, bug))
      QueueNewed(Concrete(id))
    }
    QueuePut(reference, item) => {
      system.queues[concrete_queue_index(reference)].put(item)
      QueuePutDone
    }
    QueueGet(reference) =>
      QueueGot(system.queues[concrete_queue_index(reference)].get())
    QueueSize(reference) =>
      QueueSized(system.queues[concrete_queue_index(reference)].size())
  }
}

///|
fn queue_name(command : QueueCommand) -> String {
  match command {
    QueueNew(_) => "new"
    QueuePut(_, _) => "put"
    QueueGet(_) => "get"
    QueueSize(_) => "size"
  }
}

///|
fn queue_reify_ref(
  reference : @quickcheck_statemachine.Ref[QueueId],
  environment : @quickcheck_statemachine.Environment[QueueId],
) -> Result[
  @quickcheck_statemachine.Ref[QueueId],
  @quickcheck_statemachine.EnvError,
] {
  match reference {
    Concrete(queue_id) => Ok(Concrete(queue_id))
    Symbolic(fresh_var) =>
      match environment.lookup(fresh_var) {
        Ok(queue_id) => Ok(Concrete(queue_id))
        Err(error) => Err(error)
      }
  }
}

///|
fn queue_reify_command(
  command : QueueCommand,
  environment : @quickcheck_statemachine.Environment[QueueId],
) -> Result[QueueCommand, @quickcheck_statemachine.EnvError] {
  match command {
    QueueNew(capacity) => Ok(QueueNew(capacity))
    QueuePut(reference, item) =>
      match queue_reify_ref(reference, environment) {
        Ok(concrete) => Ok(QueuePut(concrete, item))
        Err(error) => Err(error)
      }
    QueueGet(reference) =>
      match queue_reify_ref(reference, environment) {
        Ok(concrete) => Ok(QueueGet(concrete))
        Err(error) => Err(error)
      }
    QueueSize(reference) =>
      match queue_reify_ref(reference, environment) {
        Ok(concrete) => Ok(QueueSize(concrete))
        Err(error) => Err(error)
      }
  }
}

///|
fn queue_bind_response(
  symbolic : QueueResponse,
  concrete : QueueResponse,
  environment : @quickcheck_statemachine.Environment[QueueId],
) -> Result[
  @quickcheck_statemachine.Environment[QueueId],
  @quickcheck_statemachine.BindError,
] {
  match (symbolic, concrete) {
    (QueueNewed(Symbolic(fresh_var)), QueueNewed(Concrete(queue_id))) =>
      Ok(environment.insert(fresh_var, queue_id))
    (QueueNewed(Symbolic(_)), _) =>
      Err(BindMessage("expected concrete queue id"))
    _ => Ok(environment)
  }
}

///|
fn queue_remap_ref(
  reference : @quickcheck_statemachine.Ref[QueueId],
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> @quickcheck_statemachine.Ref[QueueId]? {
  match reference {
    Concrete(queue_id) => Some(Concrete(queue_id))
    Symbolic(fresh_var) =>
      match scope.get(fresh_var) {
        Some(next_var) => Some(Symbolic(next_var))
        None => None
      }
  }
}

///|
fn queue_remap_command(
  command : QueueCommand,
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> QueueCommand? {
  match command {
    QueueNew(capacity) => Some(QueueNew(capacity))
    QueuePut(reference, item) =>
      match queue_remap_ref(reference, scope) {
        Some(next_reference) => Some(QueuePut(next_reference, item))
        None => None
      }
    QueueGet(reference) =>
      match queue_remap_ref(reference, scope) {
        Some(next_reference) => Some(QueueGet(next_reference))
        None => None
      }
    QueueSize(reference) =>
      match queue_remap_ref(reference, scope) {
        Some(next_reference) => Some(QueueSize(next_reference))
        None => None
      }
  }
}

///|
fn queue_shrinker(
  _model : QueueState,
  command : QueueCommand,
) -> Array[QueueCommand] {
  match command {
    QueueNew(capacity) =>
      if capacity <= 1 {
        []
      } else {
        [QueueNew(1), QueueNew(capacity / 2)]
      }
    QueuePut(reference, item) =>
      if item == 0 {
        []
      } else {
        [QueuePut(reference, 0), QueuePut(reference, item / 2)]
      }
    QueueGet(_) | QueueSize(_) => []
  }
}

///|
fn queue_random_generator(
  model : QueueState,
  size : Int,
  rng : @splitmix.RandomState,
) -> QueueCommand? {
  ignore(size)
  let choices : Array[QueueCommand] = []
  choices.push(QueueNew(1 + rng.next_positive_int() % 3))
  for queue in model.queues {
    choices.push(QueueSize(queue.reference))
    if queue.elems.length() < queue.capacity {
      choices.push(QueuePut(queue.reference, rng.next_positive_int() % 4))
    }
    if queue.elems.length() > 0 {
      choices.push(QueueGet(queue.reference))
    }
  }
  Some(choices[rng.next_positive_int() % choices.length()])
}

///|
fn queue_base_spec(
  generator : (QueueState, Int, @splitmix.RandomState) -> QueueCommand?,
  bug? : QueueBug = QueueNoBug,
  precondition? : (QueueState, QueueCommand) -> @quickcheck_statemachine.Logic = queue_precondition,
) -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  QueueId,
  QueueSystem,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => { queues: [] },
    init_concrete_model=() => { queues: [] },
    init_system=() => { queues: [] },
    generator~,
    mock=queue_mock,
    response_vars=queue_response_vars,
    transition_symbolic=queue_transition,
    transition_concrete=queue_transition,
    precondition~,
    reify_command=queue_reify_command,
    run_command=(command, system) => run_queue_command(command, system, bug),
    bind_response=queue_bind_response,
    postcondition=queue_postcondition,
    shrinker=queue_shrinker,
    remap_command=queue_remap_command,
    command_name=queue_name,
  )
}

///|
fn queue_script_spec(
  commands : Array[QueueCommand],
  bug? : QueueBug = QueueNoBug,
  precondition? : (QueueState, QueueCommand) -> @quickcheck_statemachine.Logic = queue_precondition,
) -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  QueueId,
  QueueSystem,
] {
  let cursor : Array[Int] = [0]
  queue_base_spec(
    (model, size, rng) => {
      ignore(model)
      ignore(size)
      ignore(rng)
      let index = cursor[0]
      if index < commands.length() {
        cursor[0] = index + 1
        Some(commands[index])
      } else {
        None
      }
    },
    bug~,
    precondition~,
  )
}

///|
fn queue_random_spec(
  bug? : QueueBug = QueueNoBug,
) -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  QueueId,
  QueueSystem,
] {
  queue_base_spec(queue_random_generator, bug~)
}

///|
fn queue_symbolic_ref(id : Int) -> @quickcheck_statemachine.Ref[QueueId] {
  Symbolic(@quickcheck_statemachine.Var::{ id, })
}

///|
fn queue_full_probe_spec() -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  QueueId,
  QueueSystem,
] {
  queue_base_spec((model, size, rng) => {
    ignore(size)
    ignore(rng)
    if model.queues.length() == 0 {
      Some(QueueNew(1))
    } else {
      let reference = model.queues[0].reference
      if model.queues[0].elems.length() == 0 {
        Some(QueuePut(reference, 1))
      } else {
        Some(QueuePut(reference, 0))
      }
    }
  })
}

///|
// Blog counterexample before adding `QueueIsFull`:
// `New 1, Put q 0, Put q 1, Get q` fails against the original circular buffer
// because the second put overwrites the only slot, while the fake still models a
// FIFO queue containing both values.
test "queue blog full counterexample fails without full precondition" {
  let q0 = queue_symbolic_ref(0)
  let commands : Array[QueueCommand] = [
    QueueNew(1),
    QueuePut(q0, 0),
    QueuePut(q0, 1),
    QueueGet(q0),
  ]
  let result = @quickcheck_statemachine.check(
    queue_script_spec(
      commands,
      bug=QueueCapacityBug,
      precondition=queue_precondition_without_full_check,
    ),
    config=case_config(max_commands=commands.length(), shrink=false),
  )
  guard result
    is Err(PostconditionFailed(step_index~, command~, response~, model~, ..)) else {
    fail("expected the blog queue-full counterexample")
  }
  assert_eq(step_index, 3)
  assert_true(command is QueueGet(_))
  assert_true(response is QueueGot(1))
  assert_eq(model.queues.length(), 1)
  assert_eq(model.queues[0].elems.length(), 2)
  assert_eq(model.queues[0].elems[0], 0)
}

///|
// Precondition regression:
// The generator intentionally tries to put into a capacity-one queue after it is
// full. The property is not about the circular buffer response; it checks that
// the state-machine runner consults the model before execution and returns a
// deadlock with the already-generated prefix.
test "queue full command is rejected by precondition" {
  let result = @quickcheck_statemachine.check(
    queue_full_probe_spec(),
    config=case_config(max_commands=4, max_tries=3),
  )
  guard result
    is Err(
      GenerationFailed(failure=Deadlock(step_index~, model~, commands~, ..), ..)
    ) else {
    fail("expected queue full generation failure")
  }
  inspect(step_index, content="2")
  inspect(
    @quickcheck_statemachine.format_commands(commands),
    content=(
      #|0: QueueNew(1) -> QueueNewed(Symbolic({ id: 0 }))
      #|1: QueuePut(Symbolic({ id: 0 }), 1) -> QueuePutDone
      #|
    ),
  )
  inspect(
    @debug.to_string(model),
    content="{ queues: [{ reference: Symbolic({ id: 0 }), elems: [1], capacity: 1 }] }",
  )
}

///|
// Blog-style random property:
// This is the successful analogue of `quickCheck prop_queue`: generated symbolic
// queue handles are bound to concrete queue ids during replay, and every response
// is checked against the FIFO fake.
test "queue random generation passes with corrected circular buffer" {
  let summary = @quickcheck_statemachine.assert_check(
    queue_random_spec(),
    config=case_config(cases=100, max_commands=80, required_command_names=[
      "new", "put", "get", "size",
    ]),
  )
  inspect(summary.cases_run, content="100")
  inspect(summary.commands_run, content="8000")
}

///|
// Blog regression after adding `Size` to the generator:
// With the original allocation bug, a capacity-one queue uses one slot. After one
// put, the circular index wraps back to zero, so `Size` reports zero instead of
// the FIFO model's one element.
test "queue blog size counterexample catches capacity bug" {
  let q0 = queue_symbolic_ref(0)
  let commands : Array[QueueCommand] = [
    QueueNew(1),
    QueuePut(q0, 0),
    QueueSize(q0),
  ]
  let result = @quickcheck_statemachine.check(
    queue_script_spec(commands, bug=QueueCapacityBug),
    config=case_config(max_commands=commands.length(), shrink=false),
  )
  guard result
    is Err(PostconditionFailed(step_index~, command~, response~, model~, ..)) else {
    fail("expected the blog capacity size counterexample")
  }
  assert_eq(step_index, 2)
  assert_true(command is QueueSize(_))
  assert_true(response is QueueSized(0))
  assert_eq(model.queues.length(), 1)
  assert_eq(model.queues[0].elems.length(), 1)
}

///|
// Blog regression after fixing allocation but before fixing wrapped sizes:
// Raw signed remainder can return `-1` after the output index has advanced past
// the input index.
test "queue blog raw modulo counterexample catches negative size bug" {
  let q0 = queue_symbolic_ref(0)
  let commands : Array[QueueCommand] = [
    QueueNew(1),
    QueuePut(q0, 0),
    QueueGet(q0),
    QueuePut(q0, 0),
    QueueSize(q0),
  ]
  let result = @quickcheck_statemachine.check(
    queue_script_spec(commands, bug=QueueRawSizeBug),
    config=case_config(max_commands=commands.length(), shrink=false),
  )
  guard result
    is Err(PostconditionFailed(step_index~, command~, response~, model~, ..)) else {
    fail("expected the blog raw modulo size counterexample")
  }
  assert_eq(step_index, 4)
  assert_true(command is QueueSize(_))
  assert_true(response is QueueSized(-1))
  assert_eq(model.queues.length(), 1)
  assert_eq(model.queues[0].elems.length(), 1)
}

///|
// Blog regression after the attempted `abs` fix:
// `abs(input - output)` happens to work for capacity-one queues, but it
// undercounts once a larger queue wraps around.
test "queue blog abs size counterexample catches wrapped size bug" {
  let q0 = queue_symbolic_ref(0)
  let commands : Array[QueueCommand] = [
    QueueNew(2),
    QueuePut(q0, 0),
    QueuePut(q0, 0),
    QueueGet(q0),
    QueuePut(q0, 0),
    QueueSize(q0),
  ]
  let result = @quickcheck_statemachine.check(
    queue_script_spec(commands, bug=QueueAbsSizeBug),
    config=case_config(max_commands=commands.length(), shrink=false),
  )
  guard result
    is Err(PostconditionFailed(step_index~, command~, response~, model~, ..)) else {
    fail("expected the blog abs size counterexample")
  }
  assert_eq(step_index, 5)
  assert_true(command is QueueSize(_))
  assert_true(response is QueueSized(1))
  assert_eq(model.queues.length(), 1)
  assert_eq(model.queues[0].elems.length(), 2)
}

///|
// Circular-buffer size regression:
// The queue example shows that size bugs often survive trivial capacity-one
// tests and only appear after the input/output indices wrap. These two scripts
// pin both cases: a one-element queue and a wraparound sequence where the
// correct size formula must account for modulo arithmetic rather than an
// absolute difference.
test "queue size regressions pass with corrected circular buffer" {
  let q0 = queue_symbolic_ref(0)
  let size_one : Array[QueueCommand] = [
    QueueNew(1),
    QueuePut(q0, 0),
    QueueSize(q0),
  ]
  let summary_one = @quickcheck_statemachine.assert_check(
    queue_script_spec(size_one),
    config=case_config(max_commands=size_one.length()),
  )
  inspect(summary_one.commands_run, content="3")
  inspect(
    @quickcheck_statemachine.format_history(summary_one.history),
    content=(
      #|Invocation(pid={ id: 0 }, command=QueueNew(1))
      #|Response(pid={ id: 0 }, response=QueueNewed(Concrete({ id: 0 })))
      #|Invocation(pid={ id: 1 }, command=QueuePut(Concrete({ id: 0 }), 0))
      #|Response(pid={ id: 1 }, response=QueuePutDone)
      #|Invocation(pid={ id: 2 }, command=QueueSize(Concrete({ id: 0 })))
      #|Response(pid={ id: 2 }, response=QueueSized(1))
      #|
    ),
  )
  let wraparound : Array[QueueCommand] = [
    QueueNew(2),
    QueuePut(q0, 0),
    QueuePut(q0, 1),
    QueueGet(q0),
    QueuePut(q0, 2),
    QueueSize(q0),
  ]
  let summary_wraparound = @quickcheck_statemachine.assert_check(
    queue_script_spec(wraparound),
    config=case_config(max_commands=wraparound.length()),
  )
  inspect(summary_wraparound.commands_run, content="6")
  inspect(
    @quickcheck_statemachine.format_history(summary_wraparound.history),
    content=(
      #|Invocation(pid={ id: 0 }, command=QueueNew(2))
      #|Response(pid={ id: 0 }, response=QueueNewed(Concrete({ id: 0 })))
      #|Invocation(pid={ id: 1 }, command=QueuePut(Concrete({ id: 0 }), 0))
      #|Response(pid={ id: 1 }, response=QueuePutDone)
      #|Invocation(pid={ id: 2 }, command=QueuePut(Concrete({ id: 0 }), 1))
      #|Response(pid={ id: 2 }, response=QueuePutDone)
      #|Invocation(pid={ id: 3 }, command=QueueGet(Concrete({ id: 0 })))
      #|Response(pid={ id: 3 }, response=QueueGot(0))
      #|Invocation(pid={ id: 4 }, command=QueuePut(Concrete({ id: 0 }), 2))
      #|Response(pid={ id: 4 }, response=QueuePutDone)
      #|Invocation(pid={ id: 5 }, command=QueueSize(Concrete({ id: 0 })))
      #|Response(pid={ id: 5 }, response=QueueSized(2))
      #|
    ),
  )
}

///|
// Bug-finding regressions:
// The same random state-machine property catches the historical circular-buffer
// mistakes after `Size` is part of the generator: allocating only `capacity`
// slots, and then using absolute difference for wrapped sizes.
test "queue random generation catches capacity size bug" {
  let result = @quickcheck_statemachine.check(
    queue_random_spec(bug=QueueCapacityBug),
    config=case_config(cases=100, max_commands=20),
  )
  guard result
    is Err(PostconditionFailed(command~, response~, commands~, shrinks~, ..)) else {
    fail("expected generated queue capacity bug")
  }
  assert_true(command is QueueSize(_))
  assert_true(response is QueueSized(_))
  assert_true(commands.length() >= 3)
  assert_true(shrinks > 0)
}

///|
test "queue random generation catches wrapped size bug" {
  let result = @quickcheck_statemachine.check(
    queue_random_spec(bug=QueueAbsSizeBug),
    config=case_config(cases=100, max_commands=40),
  )
  guard result
    is Err(PostconditionFailed(command~, response~, commands~, shrinks~, ..)) else {
    fail("expected generated queue wrapped size bug")
  }
  assert_true(command is QueueSize(_))
  assert_true(response is QueueSized(_))
  assert_true(commands.length() >= 6)
  assert_true(shrinks > 0)
}
