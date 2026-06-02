///|
/// Logical process id used to pair an invocation with its response.
///
/// Sequential runs use the step index as the pid. Parallel checking can assign
/// different ids to operations that overlap in time and then search for a valid
/// linearization of those operations.
pub(all) struct Pid {
  id : Int
} derive(Eq, Hash, Debug)

///|
/// One event in an execution trace.
///
/// A complete operation normally appears as an `Invocation` followed later by a
/// `Response`. If the system under test raises, the matching terminal event is
/// an `Exception` instead.
pub(all) enum HistoryEvent[C, R] {
  Invocation(pid~ : Pid, command~ : C)
  Response(pid~ : Pid, response~ : R)
  Exception(pid~ : Pid, message~ : String)
} derive(Eq, Debug)

///|
/// Ordered trace of command invocations, responses, and exceptions.
///
/// The history is kept in the same representation used by state-machine
/// testing literature: it records observable calls rather than only final
/// results, which is the information needed for counterexamples and future
/// linearizability checks.
pub(all) struct History[C, R] {
  events : Array[HistoryEvent[C, R]]
} derive(Eq, Debug)

///|
/// Creates an empty execution trace.
pub fn[C, R] History::empty() -> History[C, R] {
  { events: [] }
}

///|
/// Returns a copy of the trace with one more event appended.
pub fn[C, R] History::push(
  self : History[C, R],
  event : HistoryEvent[C, R],
) -> History[C, R] {
  let events = self.events.copy()
  events.push(event)
  { events, }
}

///|
/// Invocation paired with its eventual response or exception.
///
/// This derived view is easier to inspect and format than the raw event stream.
pub(all) struct Operation[C, R] {
  pid : Pid
  command : C
  response : R?
  exception : String?
} derive(Eq, Debug)

///|
/// Groups a raw history into operations by matching events with the same pid.
///
/// Responses are matched with the most recent unfinished invocation for the pid.
/// This supports traces where operations from several pids are interleaved.
pub fn[C, R] make_operations(history : History[C, R]) -> Array[Operation[C, R]] {
  let operations : Array[Operation[C, R]] = []
  for event in history.events {
    match event {
      Invocation(pid~, command~) =>
        operations.push({ pid, command, response: None, exception: None })
      Response(pid~, response~) =>
        for index = operations.length() - 1; index >= 0; {
          if operations[index].pid == pid && operations[index].response is None {
            operations[index] = {
              pid,
              command: operations[index].command,
              response: Some(response),
              exception: None,
            }
            break
          } else {
            continue index - 1
          }
        }
      Exception(pid~, message~) =>
        for index = operations.length() - 1; index >= 0; {
          if operations[index].pid == pid && operations[index].exception is None {
            operations[index] = {
              pid,
              command: operations[index].command,
              response: None,
              exception: Some(message),
            }
            break
          } else {
            continue index - 1
          }
        }
    }
  }
  operations
}
