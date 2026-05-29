///|
// Queue model and property:
// `QueueState` is the pure fake used as the specification. It stores each queue
// as a normal FIFO array plus a fixed capacity; `QueueSystem` is the mutable
// circular-buffer implementation. The tested property is that each concrete
// response (`new`, `put`, `get`, `size`) matches the response predicted by the
// pure FIFO model, including wraparound cases that are hard to cover with a few
// example-based tests.
struct QueueModel {
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
  QueuePut(Int, Int)
  QueueGet(Int)
  QueueSize(Int)
} derive(Eq, Debug)

///|
enum QueueResponse {
  QueueNewed(Int)
  QueuePutDone
  QueueGot(Int)
  QueueSized(Int)
} derive(Eq, Debug)

///|
struct CircularQueue {
  slots : Array[Int]
  mut input : Int
  mut output : Int
} derive(Eq, Debug)

///|
struct QueueSystem {
  queues : Array[CircularQueue]
} derive(Eq, Debug)

///|
fn CircularQueue::new(capacity : Int) -> CircularQueue {
  let slots : Array[Int] = []
  for _ in 0..<(capacity + 1) {
    slots.push(0)
  }
  { slots, input: 0, output: 0 }
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
  (self.input - self.output + self.slots.length()) % self.slots.length()
}

///|
fn queue_exists(model : QueueState, id : Int) -> Bool {
  0 <= id && id < model.queues.length()
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
    QueuePut(id, _) =>
      if queue_exists(model, id) {
        model.queues[id].elems.length() < model.queues[id].capacity
      } else {
        false
      }
    QueueGet(id) =>
      if queue_exists(model, id) {
        model.queues[id].elems.length() > 0
      } else {
        false
      }
    QueueSize(id) => queue_exists(model, id)
  }
  @quickcheck_statemachine.Logic::predicate(name="queue precondition", value=ok)
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
fn queue_update(model : QueueState, id : Int, queue : QueueModel) -> QueueState {
  let queues = model.queues.copy()
  queues[id] = queue
  { queues, }
}

///|
fn queue_transition(model : QueueState, command : QueueCommand) -> QueueState {
  match command {
    QueueNew(capacity) => {
      let queues = model.queues.copy()
      queues.push({ elems: [], capacity })
      { queues, }
    }
    QueuePut(id, item) => {
      let queue = model.queues[id]
      let elems = queue.elems.copy()
      elems.push(item)
      queue_update(model, id, { elems, capacity: queue.capacity })
    }
    QueueGet(id) => {
      let queue = model.queues[id]
      queue_update(model, id, {
        elems: array_tail(queue.elems),
        capacity: queue.capacity,
      })
    }
    QueueSize(_) => model
  }
}

///|
fn queue_expected(model : QueueState, command : QueueCommand) -> QueueResponse {
  match command {
    QueueNew(_) => QueueNewed(model.queues.length())
    QueuePut(_, _) => QueuePutDone
    QueueGet(id) => QueueGot(model.queues[id].elems[0])
    QueueSize(id) => QueueSized(model.queues[id].elems.length())
  }
}

///|
fn run_queue_command(
  command : QueueCommand,
  system : QueueSystem,
) -> QueueResponse {
  match command {
    QueueNew(capacity) => {
      let id = system.queues.length()
      system.queues.push(CircularQueue::new(capacity))
      QueueNewed(id)
    }
    QueuePut(id, item) => {
      system.queues[id].put(item)
      QueuePutDone
    }
    QueueGet(id) => QueueGot(system.queues[id].get())
    QueueSize(id) => QueueSized(system.queues[id].size())
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
fn queue_base_spec(
  generator : (QueueState, Int, @splitmix.RandomState) -> QueueCommand?,
) -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  Unit,
  QueueSystem,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=() => { queues: [] },
    init_concrete_model=() => { queues: [] },
    init_system=() => { queues: [] },
    generator~,
    mock=(model, command, gen_sym) => (queue_expected(model, command), gen_sym),
    transition_symbolic=(model, command, response) => {
      ignore(response)
      queue_transition(model, command)
    },
    transition_concrete=(model, command, response) => {
      ignore(response)
      queue_transition(model, command)
    },
    precondition=queue_precondition,
    reify_command=(command, environment) => {
      ignore(environment)
      Ok(command)
    },
    run_command=(command, system) => run_queue_command(command, system),
    bind_response=(symbolic, concrete, environment) => {
      ignore(symbolic)
      ignore(concrete)
      Ok(environment)
    },
    postcondition=(model, command, response) => {
      @quickcheck_statemachine.Logic::predicate(
        name="queue response matches model",
        value=response == queue_expected(model, command),
      )
    },
    command_name=queue_name,
  )
}

///|
fn queue_script_spec(
  commands : Array[QueueCommand],
) -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  Unit,
  QueueSystem,
] {
  let cursor : Array[Int] = [0]
  queue_base_spec((model, size, rng) => {
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
  })
}

///|
fn queue_full_probe_spec() -> @quickcheck_statemachine.StateMachine[
  QueueState,
  QueueState,
  QueueCommand,
  QueueCommand,
  QueueResponse,
  QueueResponse,
  Unit,
  QueueSystem,
] {
  queue_base_spec((model, size, rng) => {
    ignore(size)
    ignore(rng)
    if model.queues.length() == 0 {
      Some(QueueNew(1))
    } else if model.queues[0].elems.length() == 0 {
      Some(QueuePut(0, 1))
    } else {
      Some(QueuePut(0, 0))
    }
  })
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
      #|0: QueueNew(1) -> QueueNewed(0)
      #|1: QueuePut(0, 1) -> QueuePutDone
      #|
    ),
  )
  inspect(
    @debug.to_string(model),
    content="{ queues: [{ elems: [1], capacity: 1 }] }",
  )
}

///|
// Circular-buffer size regression:
// The queue example shows that size bugs often survive trivial capacity-one
// tests and only appear after the input/output indices wrap. These two scripts
// pin both cases: a one-element queue and a wraparound sequence where the
// correct size formula must account for modulo arithmetic rather than an
// absolute difference.
test "queue size regressions pass with corrected circular buffer" {
  let size_one : Array[QueueCommand] = [
    QueueNew(1),
    QueuePut(0, 0),
    QueueSize(0),
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
      #|Response(pid={ id: 0 }, response=QueueNewed(0))
      #|Invocation(pid={ id: 1 }, command=QueuePut(0, 0))
      #|Response(pid={ id: 1 }, response=QueuePutDone)
      #|Invocation(pid={ id: 2 }, command=QueueSize(0))
      #|Response(pid={ id: 2 }, response=QueueSized(1))
      #|
    ),
  )
  let wraparound : Array[QueueCommand] = [
    QueueNew(2),
    QueuePut(0, 0),
    QueuePut(0, 1),
    QueueGet(0),
    QueuePut(0, 2),
    QueueSize(0),
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
      #|Response(pid={ id: 0 }, response=QueueNewed(0))
      #|Invocation(pid={ id: 1 }, command=QueuePut(0, 0))
      #|Response(pid={ id: 1 }, response=QueuePutDone)
      #|Invocation(pid={ id: 2 }, command=QueuePut(0, 1))
      #|Response(pid={ id: 2 }, response=QueuePutDone)
      #|Invocation(pid={ id: 3 }, command=QueueGet(0))
      #|Response(pid={ id: 3 }, response=QueueGot(0))
      #|Invocation(pid={ id: 4 }, command=QueuePut(0, 2))
      #|Response(pid={ id: 4 }, response=QueuePutDone)
      #|Invocation(pid={ id: 5 }, command=QueueSize(0))
      #|Response(pid={ id: 5 }, response=QueueSized(2))
      #|
    ),
  )
}
