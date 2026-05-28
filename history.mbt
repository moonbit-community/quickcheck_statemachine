///|
pub(all) struct Pid {
  id : Int
} derive(Eq, Hash, Debug)

///|
pub(all) enum HistoryEvent[C, R] {
  Invocation(pid~ : Pid, command~ : C)
  Response(pid~ : Pid, response~ : R)
  Exception(pid~ : Pid, message~ : String)
} derive(Eq, Debug)

///|
pub(all) struct History[C, R] {
  events : Array[HistoryEvent[C, R]]
} derive(Eq, Debug)

///|
pub fn[C, R] History::empty() -> History[C, R] {
  { events: [] }
}

///|
pub fn[C, R] History::push(
  self : History[C, R],
  event : HistoryEvent[C, R],
) -> History[C, R] {
  let events = self.events.copy()
  events.push(event)
  { events, }
}

///|
pub(all) struct Operation[C, R] {
  pid : Pid
  command : C
  response : R?
  exception : String?
} derive(Eq, Debug)

///|
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
