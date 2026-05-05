///|
// File-system model and property:
// The concrete model records directories, file contents, open handles,
// and the next handle id. The symbolic model mirrors that state but represents
// handles returned by `open` as `Var`s, so the full command program can be
// generated before any real handle exists. The core property is that each real
// response agrees with the pure file-system model after reifying symbolic
// handles through the execution environment.
struct FsDir {
  parts : Array[String]
} derive(Eq, Debug)

///|
struct FsFile {
  dir : FsDir
  name : String
} derive(Eq, Debug)

///|
struct FsFileEntry {
  file : FsFile
  content : String
} derive(Eq, Debug)

///|
struct FsOpenEntry {
  handle : Int
  file : FsFile
} derive(Eq, Debug)

///|
// Concrete model:
// This is the pure fake/reference implementation. `dirs` and `files` describe
// durable file-system state, `handles` tracks currently open handles, and
// `next_handle` predicts the next concrete handle returned by a successful open.
struct FsModel {
  dirs : Array[FsDir]
  files : Array[FsFileEntry]
  handles : Array[FsOpenEntry]
  next_handle : Int
} derive(Eq, Debug)

///|
struct FsSystem {
  dirs : Array[FsDir]
  files : Array[FsFileEntry]
  mut handles : Array[FsOpenEntry]
  mut next_handle : Int
} derive(Eq, Debug)

///|
enum FsErr {
  FsAlreadyExists
  FsDoesNotExist
  FsHandleClosed
  FsBusy
} derive(Eq, Debug)

///|
enum FsCommand {
  FsMkDir(FsDir)
  FsOpen(FsFile)
  FsWrite(Int, String)
  FsClose(Int)
  FsRead(FsFile)
} derive(Eq, Debug)

///|
enum FsSuccess {
  FsUnit
  FsHandle(Int)
  FsText(String)
} derive(Eq, Debug)

///|
enum FsResponse {
  FsSucceeded(FsSuccess)
  FsFailed(FsErr)
} derive(Eq, Debug)

///|
enum FsConcreteValue {
  FsHandleValue(Int)
} derive(Eq, Debug)

///|
struct FsSymOpenEntry {
  handle : @quickcheck_statemachine.Var
  file : FsFile
} derive(Eq, Debug)

///|
// Symbolic model:
// During generation we know which symbolic handles have been created, but not
// their concrete values. `handles` tracks currently open symbolic handles, while
// `created_handles` deliberately keeps closed handles as valid references so
// tests can exercise the `HandleClosed` error path.
struct FsSymModel {
  dirs : Array[FsDir]
  files : Array[FsFileEntry]
  handles : Array[FsSymOpenEntry]
  created_handles : Array[@quickcheck_statemachine.Var]
} derive(Eq, Debug)

///|
enum FsSymCommand {
  FsSymMkDir(FsDir)
  FsSymOpen(FsFile)
  FsSymWrite(@quickcheck_statemachine.Ref[FsConcreteValue], String)
  FsSymClose(@quickcheck_statemachine.Ref[FsConcreteValue])
  FsSymRead(FsFile)
} derive(Eq, Debug)

///|
enum FsSymSuccess {
  FsSymUnit
  FsSymHandle(@quickcheck_statemachine.Var)
  FsSymText(String)
} derive(Eq, Debug)

///|
enum FsSymResponse {
  FsSymSucceeded(FsSymSuccess)
  FsSymFailed(FsErr)
} derive(Eq, Debug)

///|
fn fs_dir(parts : Array[String]) -> FsDir {
  FsDir::{ parts, }
}

///|
fn fs_file(dir : FsDir, name : String) -> FsFile {
  FsFile::{ dir, name }
}

///|
fn fs_root_dir() -> FsDir {
  fs_dir([])
}

///|
fn fs_empty_model() -> FsModel {
  FsModel::{ dirs: [fs_root_dir()], files: [], handles: [], next_handle: 0 }
}

///|
fn fs_empty_sym_model() -> FsSymModel {
  FsSymModel::{
    dirs: [fs_root_dir()],
    files: [],
    handles: [],
    created_handles: [],
  }
}

///|
fn fs_new_system() -> FsSystem {
  FsSystem::{ dirs: [fs_root_dir()], files: [], handles: [], next_handle: 0 }
}

///|
fn fs_dir_exists(dirs : Array[FsDir], dir : FsDir) -> Bool {
  for i = 0; i < dirs.length(); {
    if dirs[i] == dir {
      break true
    } else {
      continue i + 1
    }
  } nobreak {
    false
  }
}

///|
fn fs_parent_dir(dir : FsDir) -> FsDir? {
  let len = dir.parts.length()
  if len == 0 {
    None
  } else {
    let parts : Array[String] = []
    for i in 0..<(len - 1) {
      parts.push(dir.parts[i])
    }
    Some(FsDir::{ parts, })
  }
}

///|
fn fs_parent_exists(dirs : Array[FsDir], dir : FsDir) -> Bool {
  match fs_parent_dir(dir) {
    None => true
    Some(parent) => fs_dir_exists(dirs, parent)
  }
}

///|
fn fs_file_index(files : Array[FsFileEntry], file : FsFile) -> Int? {
  for i = 0; i < files.length(); {
    if files[i].file == file {
      break Some(i)
    } else {
      continue i + 1
    }
  } nobreak {
    None
  }
}

///|
fn fs_open_index(handles : Array[FsOpenEntry], handle : Int) -> Int? {
  for i = 0; i < handles.length(); {
    if handles[i].handle == handle {
      break Some(i)
    } else {
      continue i + 1
    }
  } nobreak {
    None
  }
}

///|
fn fs_sym_open_index(
  handles : Array[FsSymOpenEntry],
  handle : @quickcheck_statemachine.Var,
) -> Int? {
  for i = 0; i < handles.length(); {
    if handles[i].handle == handle {
      break Some(i)
    } else {
      continue i + 1
    }
  } nobreak {
    None
  }
}

///|
fn fs_sym_handle_created(
  model : FsSymModel,
  handle : @quickcheck_statemachine.Var,
) -> Bool {
  for created in model.created_handles {
    if created == handle {
      return true
    }
  }
  false
}

///|
fn fs_file_is_open(handles : Array[FsOpenEntry], file : FsFile) -> Bool {
  for i = 0; i < handles.length(); {
    if handles[i].file == file {
      break true
    } else {
      continue i + 1
    }
  } nobreak {
    false
  }
}

///|
fn fs_sym_file_is_open(handles : Array[FsSymOpenEntry], file : FsFile) -> Bool {
  for i = 0; i < handles.length(); {
    if handles[i].file == file {
      break true
    } else {
      continue i + 1
    }
  } nobreak {
    false
  }
}

///|
fn fs_write_file(
  files : Array[FsFileEntry],
  file : FsFile,
  content : String,
) -> Array[FsFileEntry] {
  let next = files.copy()
  match fs_file_index(next, file) {
    Some(index) => next[index] = FsFileEntry::{ file, content }
    None => next.push(FsFileEntry::{ file, content })
  }
  next
}

///|
fn fs_remove_open(
  handles : Array[FsOpenEntry],
  handle : Int,
) -> Array[FsOpenEntry] {
  let next : Array[FsOpenEntry] = []
  for entry in handles {
    if entry.handle != handle {
      next.push(entry)
    }
  }
  next
}

///|
fn fs_sym_remove_open(
  handles : Array[FsSymOpenEntry],
  handle : @quickcheck_statemachine.Var,
) -> Array[FsSymOpenEntry] {
  let next : Array[FsSymOpenEntry] = []
  for entry in handles {
    if entry.handle != handle {
      next.push(entry)
    }
  }
  next
}

///|
fn fs_model_mkdir(model : FsModel, dir : FsDir) -> (FsResponse, FsModel) {
  if fs_dir_exists(model.dirs, dir) {
    (FsFailed(FsAlreadyExists), model)
  } else if !fs_parent_exists(model.dirs, dir) {
    (FsFailed(FsDoesNotExist), model)
  } else {
    let dirs = model.dirs.copy()
    dirs.push(dir)
    (
      FsSucceeded(FsUnit),
      FsModel::{
        dirs,
        files: model.files,
        handles: model.handles,
        next_handle: model.next_handle,
      },
    )
  }
}

///|
fn fs_model_open(model : FsModel, file : FsFile) -> (FsResponse, FsModel) {
  if !fs_dir_exists(model.dirs, file.dir) {
    (FsFailed(FsDoesNotExist), model)
  } else if fs_file_is_open(model.handles, file) {
    (FsFailed(FsBusy), model)
  } else {
    let files = model.files.copy()
    if fs_file_index(files, file) is None {
      files.push(FsFileEntry::{ file, content: "" })
    }
    let handle = model.next_handle
    let handles = model.handles.copy()
    handles.push(FsOpenEntry::{ handle, file })
    (
      FsSucceeded(FsHandle(handle)),
      FsModel::{ dirs: model.dirs, files, handles, next_handle: handle + 1 },
    )
  }
}

///|
fn fs_model_write(
  model : FsModel,
  handle : Int,
  content : String,
) -> (FsResponse, FsModel) {
  match fs_open_index(model.handles, handle) {
    None => (FsFailed(FsHandleClosed), model)
    Some(index) => {
      let files = fs_write_file(model.files, model.handles[index].file, content)
      (
        FsSucceeded(FsUnit),
        FsModel::{
          dirs: model.dirs,
          files,
          handles: model.handles,
          next_handle: model.next_handle,
        },
      )
    }
  }
}

///|
fn fs_model_close(model : FsModel, handle : Int) -> (FsResponse, FsModel) {
  match fs_open_index(model.handles, handle) {
    None => (FsFailed(FsHandleClosed), model)
    Some(_) =>
      (
        FsSucceeded(FsUnit),
        FsModel::{
          dirs: model.dirs,
          files: model.files,
          handles: fs_remove_open(model.handles, handle),
          next_handle: model.next_handle,
        },
      )
  }
}

///|
fn fs_model_read(model : FsModel, file : FsFile) -> (FsResponse, FsModel) {
  if fs_file_is_open(model.handles, file) {
    (FsFailed(FsBusy), model)
  } else {
    match fs_file_index(model.files, file) {
      Some(index) => (FsSucceeded(FsText(model.files[index].content)), model)
      None => (FsFailed(FsDoesNotExist), model)
    }
  }
}

///|
fn fs_model_run(command : FsCommand, model : FsModel) -> (FsResponse, FsModel) {
  match command {
    FsMkDir(dir) => fs_model_mkdir(model, dir)
    FsOpen(file) => fs_model_open(model, file)
    FsWrite(handle, content) => fs_model_write(model, handle, content)
    FsClose(handle) => fs_model_close(model, handle)
    FsRead(file) => fs_model_read(model, file)
  }
}

///|
fn fs_system_mkdir(system : FsSystem, dir : FsDir) -> FsResponse {
  if fs_dir_exists(system.dirs, dir) {
    FsFailed(FsAlreadyExists)
  } else if !fs_parent_exists(system.dirs, dir) {
    FsFailed(FsDoesNotExist)
  } else {
    system.dirs.push(dir)
    FsSucceeded(FsUnit)
  }
}

///|
fn fs_system_open(system : FsSystem, file : FsFile) -> FsResponse {
  if !fs_dir_exists(system.dirs, file.dir) {
    FsFailed(FsDoesNotExist)
  } else if fs_file_is_open(system.handles, file) {
    FsFailed(FsBusy)
  } else {
    if fs_file_index(system.files, file) is None {
      system.files.push(FsFileEntry::{ file, content: "" })
    }
    let handle = system.next_handle
    system.next_handle += 1
    system.handles.push(FsOpenEntry::{ handle, file })
    FsSucceeded(FsHandle(handle))
  }
}

///|
fn fs_system_write(
  system : FsSystem,
  handle : Int,
  content : String,
) -> FsResponse {
  match fs_open_index(system.handles, handle) {
    None => FsFailed(FsHandleClosed)
    Some(index) => {
      match fs_file_index(system.files, system.handles[index].file) {
        Some(file_index) =>
          system.files[file_index] = FsFileEntry::{
            file: system.handles[index].file,
            content,
          }
        None =>
          system.files.push(FsFileEntry::{
            file: system.handles[index].file,
            content,
          })
      }
      FsSucceeded(FsUnit)
    }
  }
}

///|
fn fs_system_close(system : FsSystem, handle : Int) -> FsResponse {
  match fs_open_index(system.handles, handle) {
    None => FsFailed(FsHandleClosed)
    Some(_) => {
      system.handles = fs_remove_open(system.handles, handle)
      FsSucceeded(FsUnit)
    }
  }
}

///|
fn fs_system_read(system : FsSystem, file : FsFile) -> FsResponse {
  if fs_file_is_open(system.handles, file) {
    FsFailed(FsBusy)
  } else {
    match fs_file_index(system.files, file) {
      Some(index) => FsSucceeded(FsText(system.files[index].content))
      None => FsFailed(FsDoesNotExist)
    }
  }
}

///|
fn fs_system_read_without_busy_check(
  system : FsSystem,
  file : FsFile,
) -> FsResponse {
  match fs_file_index(system.files, file) {
    Some(index) => FsSucceeded(FsText(system.files[index].content))
    None => FsFailed(FsDoesNotExist)
  }
}

///|
fn run_fs_command(command : FsCommand, system : FsSystem) -> FsResponse {
  match command {
    FsMkDir(dir) => fs_system_mkdir(system, dir)
    FsOpen(file) => fs_system_open(system, file)
    FsWrite(handle, content) => fs_system_write(system, handle, content)
    FsClose(handle) => fs_system_close(system, handle)
    FsRead(file) => fs_system_read(system, file)
  }
}

///|
fn run_fs_command_without_busy_check(
  command : FsCommand,
  system : FsSystem,
) -> FsResponse {
  match command {
    FsRead(file) => fs_system_read_without_busy_check(system, file)
    _ => run_fs_command(command, system)
  }
}

///|
fn fs_transition(
  model : FsModel,
  command : FsCommand,
  response : FsResponse,
) -> FsModel {
  ignore(response)
  let (_, next_model) = fs_model_run(command, model)
  next_model
}

///|
// Concrete postcondition:
// Execute the same command in the pure model and compare its predicted response
// with the response observed from the mutable system. This is the lockstep
// comparison described in the QSM article: the model both predicts the response
// and advances to the next reference state.
fn fs_postcondition(
  model : FsModel,
  command : FsCommand,
  response : FsResponse,
) -> @quickcheck_statemachine.Logic {
  let (expected, _) = fs_model_run(command, model)
  @quickcheck_statemachine.Logic::predicate(
    name="filesystem response matches model",
    value=response == expected,
  )
}

///|
fn fs_sym_mkdir(model : FsSymModel, dir : FsDir) -> FsSymResponse {
  if fs_dir_exists(model.dirs, dir) {
    FsSymFailed(FsAlreadyExists)
  } else if !fs_parent_exists(model.dirs, dir) {
    FsSymFailed(FsDoesNotExist)
  } else {
    FsSymSucceeded(FsSymUnit)
  }
}

///|
fn fs_sym_open(
  model : FsSymModel,
  file : FsFile,
  gen_sym : @quickcheck_statemachine.GenSym,
) -> (FsSymResponse, @quickcheck_statemachine.GenSym) {
  if !fs_dir_exists(model.dirs, file.dir) {
    (FsSymFailed(FsDoesNotExist), gen_sym)
  } else if fs_sym_file_is_open(model.handles, file) {
    (FsSymFailed(FsBusy), gen_sym)
  } else {
    let (handle, next_gen_sym) = gen_sym.fresh()
    (FsSymSucceeded(FsSymHandle(handle)), next_gen_sym)
  }
}

///|
fn fs_sym_write(
  model : FsSymModel,
  handle : @quickcheck_statemachine.Ref[FsConcreteValue],
) -> FsSymResponse {
  match handle {
    @quickcheck_statemachine.Ref::Symbolic(var_ref) =>
      if fs_sym_open_index(model.handles, var_ref) is Some(_) {
        FsSymSucceeded(FsSymUnit)
      } else {
        FsSymFailed(FsHandleClosed)
      }
    @quickcheck_statemachine.Ref::Concrete(_) => FsSymSucceeded(FsSymUnit)
  }
}

///|
fn fs_sym_close(
  model : FsSymModel,
  handle : @quickcheck_statemachine.Ref[FsConcreteValue],
) -> FsSymResponse {
  fs_sym_write(model, handle)
}

///|
fn fs_sym_read(model : FsSymModel, file : FsFile) -> FsSymResponse {
  if fs_sym_file_is_open(model.handles, file) {
    FsSymFailed(FsBusy)
  } else {
    match fs_file_index(model.files, file) {
      Some(index) => FsSymSucceeded(FsSymText(model.files[index].content))
      None => FsSymFailed(FsDoesNotExist)
    }
  }
}

///|
// Symbolic mock response:
// Open commands allocate fresh variables with `GenSym`; later write/close
// commands can refer to those variables before execution has produced concrete
// handles. This is the MoonBit version of QSM's symbolic/concrete reference
// split.
fn fs_sym_mock(
  model : FsSymModel,
  command : FsSymCommand,
  gen_sym : @quickcheck_statemachine.GenSym,
) -> (FsSymResponse, @quickcheck_statemachine.GenSym) {
  match command {
    FsSymMkDir(dir) => (fs_sym_mkdir(model, dir), gen_sym)
    FsSymOpen(file) => fs_sym_open(model, file, gen_sym)
    FsSymWrite(handle, _) => (fs_sym_write(model, handle), gen_sym)
    FsSymClose(handle) => (fs_sym_close(model, handle), gen_sym)
    FsSymRead(file) => (fs_sym_read(model, file), gen_sym)
  }
}

///|
fn fs_sym_transition(
  model : FsSymModel,
  command : FsSymCommand,
  response : FsSymResponse,
) -> FsSymModel {
  match (command, response) {
    (FsSymMkDir(dir), FsSymSucceeded(FsSymUnit)) => {
      let dirs = model.dirs.copy()
      dirs.push(dir)
      FsSymModel::{
        dirs,
        files: model.files,
        handles: model.handles,
        created_handles: model.created_handles,
      }
    }
    (FsSymOpen(file), FsSymSucceeded(FsSymHandle(handle))) => {
      let files = model.files.copy()
      if fs_file_index(files, file) is None {
        files.push(FsFileEntry::{ file, content: "" })
      }
      let handles = model.handles.copy()
      handles.push(FsSymOpenEntry::{ handle, file })
      let created_handles = model.created_handles.copy()
      created_handles.push(handle)
      FsSymModel::{ dirs: model.dirs, files, handles, created_handles }
    }
    (
      FsSymWrite(@quickcheck_statemachine.Ref::Symbolic(handle), content),
      FsSymSucceeded(FsSymUnit),
    ) =>
      match fs_sym_open_index(model.handles, handle) {
        None => model
        Some(index) => {
          let files = fs_write_file(
            model.files,
            model.handles[index].file,
            content,
          )
          FsSymModel::{
            dirs: model.dirs,
            files,
            handles: model.handles,
            created_handles: model.created_handles,
          }
        }
      }
    (
      FsSymClose(@quickcheck_statemachine.Ref::Symbolic(handle)),
      FsSymSucceeded(FsSymUnit),
    ) =>
      FsSymModel::{
        dirs: model.dirs,
        files: model.files,
        handles: fs_sym_remove_open(model.handles, handle),
        created_handles: model.created_handles,
      }
    _ => model
  }
}

///|
// Liberal precondition:
// The QSM article stresses that preconditions should reject impossible programs,
// not interesting error cases. We reject references to handles that were never
// produced by an open command, because they cannot be reified. We still allow
// operations on closed handles so the model can check that the implementation
// returns `HandleClosed` rather than hiding that behavior from generation and
// shrinking.
fn fs_sym_precondition(
  model : FsSymModel,
  command : FsSymCommand,
) -> @quickcheck_statemachine.Logic {
  let ok = match command {
    FsSymWrite(@quickcheck_statemachine.Ref::Symbolic(handle), _)
    | FsSymClose(@quickcheck_statemachine.Ref::Symbolic(handle)) =>
      fs_sym_handle_created(model, handle)
    FsSymWrite(@quickcheck_statemachine.Ref::Concrete(_), _)
    | FsSymClose(@quickcheck_statemachine.Ref::Concrete(_)) => true
    FsSymMkDir(_) | FsSymOpen(_) | FsSymRead(_) => true
  }
  @quickcheck_statemachine.Logic::predicate(
    name="filesystem precondition",
    value=ok,
  )
}

///|
fn fs_sym_response_vars(
  response : FsSymResponse,
) -> Array[@quickcheck_statemachine.Var] {
  match response {
    FsSymSucceeded(FsSymHandle(handle)) => [handle]
    _ => []
  }
}

///|
fn fs_reify_ref(
  handle : @quickcheck_statemachine.Ref[FsConcreteValue],
  environment : @quickcheck_statemachine.Environment[FsConcreteValue],
) -> Result[Int, @quickcheck_statemachine.EnvError] {
  match handle {
    @quickcheck_statemachine.Ref::Concrete(FsHandleValue(value)) => Ok(value)
    @quickcheck_statemachine.Ref::Symbolic(var_ref) =>
      match environment.lookup(var_ref) {
        Ok(FsHandleValue(value)) => Ok(value)
        Err(error) => Err(error)
      }
  }
}

///|
fn fs_reify_command(
  command : FsSymCommand,
  environment : @quickcheck_statemachine.Environment[FsConcreteValue],
) -> Result[FsCommand, @quickcheck_statemachine.EnvError] {
  match command {
    FsSymMkDir(dir) => Ok(FsMkDir(dir))
    FsSymOpen(file) => Ok(FsOpen(file))
    FsSymWrite(handle, content) =>
      match fs_reify_ref(handle, environment) {
        Ok(value) => Ok(FsWrite(value, content))
        Err(error) => Err(error)
      }
    FsSymClose(handle) =>
      match fs_reify_ref(handle, environment) {
        Ok(value) => Ok(FsClose(value))
        Err(error) => Err(error)
      }
    FsSymRead(file) => Ok(FsRead(file))
  }
}

///|
fn fs_bind_response(
  symbolic : FsSymResponse,
  concrete : FsResponse,
  environment : @quickcheck_statemachine.Environment[FsConcreteValue],
) -> Result[
  @quickcheck_statemachine.Environment[FsConcreteValue],
  @quickcheck_statemachine.BindError,
] {
  match (symbolic, concrete) {
    (FsSymSucceeded(FsSymHandle(var_ref)), FsSucceeded(FsHandle(handle))) =>
      Ok(environment.insert(var_ref, FsHandleValue(handle)))
    (FsSymSucceeded(FsSymHandle(_)), _) =>
      Err(
        @quickcheck_statemachine.BindError::BindMessage(
          "expected concrete handle",
        ),
      )
    _ => Ok(environment)
  }
}

///|
fn fs_remap_ref(
  handle : @quickcheck_statemachine.Ref[FsConcreteValue],
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> @quickcheck_statemachine.Ref[FsConcreteValue]? {
  match handle {
    @quickcheck_statemachine.Ref::Concrete(value) =>
      Some(@quickcheck_statemachine.Ref::Concrete(value))
    @quickcheck_statemachine.Ref::Symbolic(var_ref) =>
      match scope.get(var_ref) {
        None => None
        Some(next_var) => Some(@quickcheck_statemachine.Ref::Symbolic(next_var))
      }
  }
}

///|
// Dependency-aware remapping:
// Shrinking may delete an earlier `open`. Any later command that used the
// deleted symbolic handle must then be rejected, while surviving handles are
// remapped to the fresh variables produced by the rebuilt program.
fn fs_remap_command(
  command : FsSymCommand,
  scope : Map[@quickcheck_statemachine.Var, @quickcheck_statemachine.Var],
) -> FsSymCommand? {
  match command {
    FsSymMkDir(dir) => Some(FsSymMkDir(dir))
    FsSymOpen(file) => Some(FsSymOpen(file))
    FsSymWrite(handle, content) =>
      match fs_remap_ref(handle, scope) {
        None => None
        Some(next_handle) => Some(FsSymWrite(next_handle, content))
      }
    FsSymClose(handle) =>
      match fs_remap_ref(handle, scope) {
        None => None
        Some(next_handle) => Some(FsSymClose(next_handle))
      }
    FsSymRead(file) => Some(FsSymRead(file))
  }
}

///|
fn fs_sym_name(command : FsSymCommand) -> String {
  match command {
    FsSymMkDir(_) => "mkdir"
    FsSymOpen(_) => "open"
    FsSymWrite(_, _) => "write"
    FsSymClose(_) => "close"
    FsSymRead(_) => "read"
  }
}

///|
// Labels used as coverage diagnostics:
// The file-system example in the blog uses labels to make sure generated
// programs cover meaningful behaviors, not just arbitrary command names. These
// labels identify multi-open scenarios, successful reads, closed-handle writes,
// and busy reads.
fn fs_label(
  model : FsModel,
  command : FsCommand,
  response : FsResponse,
) -> Array[String] {
  let labels : Array[String] = []
  match (command, response) {
    (FsOpen(_), FsSucceeded(FsHandle(_))) =>
      if model.handles.length() == 1 {
        labels.push("OpenTwo")
      }
    (FsRead(_), FsSucceeded(FsText(_))) => labels.push("SuccessfulRead")
    (FsWrite(_, _), FsFailed(FsHandleClosed)) =>
      labels.push("ClosedHandleWrite")
    (FsRead(_), FsFailed(FsBusy)) => labels.push("BusyRead")
    _ => ()
  }
  labels
}

///|
fn fs_script_spec(
  commands : Array[FsSymCommand],
  run_command? : (FsCommand, FsSystem) -> FsResponse = run_fs_command,
) -> @quickcheck_statemachine.StateMachine[
  FsSymModel,
  FsModel,
  FsSymCommand,
  FsCommand,
  FsSymResponse,
  FsResponse,
  FsConcreteValue,
  FsSystem,
] {
  let cursor : Array[Int] = [0]
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=fs_empty_sym_model,
    init_concrete_model=fs_empty_model,
    init_system=() => fs_new_system(),
    generator=(model, size, rng) => {
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
    mock=fs_sym_mock,
    response_vars=fs_sym_response_vars,
    transition_symbolic=fs_sym_transition,
    transition_concrete=fs_transition,
    precondition=fs_sym_precondition,
    reify_command=fs_reify_command,
    run_command=(command, system) => run_command(command, system),
    bind_response=fs_bind_response,
    remap_command=fs_remap_command,
    postcondition=fs_postcondition,
    command_name=fs_sym_name,
    label=fs_label,
  )
}

///|
fn symbolic_handle(id : Int) -> @quickcheck_statemachine.Ref[FsConcreteValue] {
  @quickcheck_statemachine.Ref::Symbolic(@quickcheck_statemachine.Var::{ id, })
}

///|
fn fs_unknown_handle_probe_spec() -> @quickcheck_statemachine.StateMachine[
  FsSymModel,
  FsModel,
  FsSymCommand,
  FsCommand,
  FsSymResponse,
  FsResponse,
  FsConcreteValue,
  FsSystem,
] {
  @quickcheck_statemachine.StateMachine::new(
    init_symbolic_model=fs_empty_sym_model,
    init_concrete_model=fs_empty_model,
    init_system=() => fs_new_system(),
    generator=(model, size, rng) => {
      ignore(model)
      ignore(size)
      ignore(rng)
      Some(FsSymWrite(symbolic_handle(0), "orphan"))
    },
    mock=fs_sym_mock,
    response_vars=fs_sym_response_vars,
    transition_symbolic=fs_sym_transition,
    transition_concrete=fs_transition,
    precondition=fs_sym_precondition,
    reify_command=fs_reify_command,
    run_command=(command, system) => run_fs_command(command, system),
    bind_response=fs_bind_response,
    remap_command=fs_remap_command,
    postcondition=fs_postcondition,
    command_name=fs_sym_name,
    label=fs_label,
  )
}

///|
// Symbolic-handle scenario:
// This hand-written program is the concrete form of 
// "open a, open b, write through the symbolic handles, close, then read". The
// property checks that the program can be generated before concrete handles
// exist, reified at execution time, and still satisfy the pure model. The
// required labels assert that the scenario covers both multiple open handles and
// at least one successful read.
test "qsm blog filesystem open-write-read examples pass with symbolic handles" {
  let root = fs_root_dir()
  let z = fs_dir(["z"])
  let a = fs_file(root, "a")
  let b = fs_file(root, "b")
  let z_b = fs_file(z, "b")
  let commands : Array[FsSymCommand] = [
    FsSymOpen(a),
    FsSymOpen(b),
    FsSymWrite(symbolic_handle(0), "Hi"),
    FsSymWrite(symbolic_handle(1), "Bye"),
    FsSymClose(symbolic_handle(0)),
    FsSymRead(a),
    FsSymClose(symbolic_handle(1)),
    FsSymRead(b),
    FsSymMkDir(z),
    FsSymOpen(z_b),
    FsSymClose(symbolic_handle(2)),
    FsSymRead(z_b),
  ]
  let summary = @quickcheck_statemachine.assert_check(
    fs_script_spec(commands),
    config=case_config(max_commands=commands.length(), required_labels=[
      "OpenTwo", "SuccessfulRead",
    ]),
  )
  assert_eq(summary.commands_run, commands.length())
}

///|
// Impossible-reference precondition:
// The generator proposes a write through `Var 0` before any open command has
// introduced that variable. The property checks that generation exhausts its
// retries and reports a deadlock at step zero instead of producing a program
// that would fail later during reification.
test "qsm blog precondition rejects handles that were never created" {
  let result = @quickcheck_statemachine.check(
    fs_unknown_handle_probe_spec(),
    config=case_config(max_commands=1, max_tries=3),
  )
  guard result
    is Err(
      @quickcheck_statemachine.RunFailure::GenerationFailed(
        failure=@quickcheck_statemachine.GenerationFailure::Deadlock(
          step_index~,
          model~,
          commands~,
          ..
        ),
        ..
      )
    ) else {
    fail("expected unknown handle to exhaust generation attempts")
  }
  assert_eq(step_index, 0)
  assert_eq(model.created_handles.length(), 0)
  assert_eq(commands.length(), 0)
}

///|
// Closed-handle error coverage:
// In contrast with the previous test, this handle was created by `open` and is
// therefore a valid symbolic reference even after `close`. The property checks
// the intentionally liberal precondition: closed-handle writes remain legal test
// commands so the model can verify the expected `HandleClosed` response and the
// label can record that coverage.
test "qsm blog precondition still allows closed handle errors" {
  let root = fs_root_dir()
  let a = fs_file(root, "a")
  let commands : Array[FsSymCommand] = [
    FsSymOpen(a),
    FsSymClose(symbolic_handle(0)),
    FsSymWrite(symbolic_handle(0), "late write"),
  ]
  let summary = @quickcheck_statemachine.assert_check(
    fs_script_spec(commands),
    config=case_config(max_commands=commands.length(), required_labels=[
      "ClosedHandleWrite",
    ]),
  )
  assert_eq(summary.commands_run, 3)
}

///|
// Busy-read bug regression:
// The pure model rejects reading a file while it has an open handle, returning
// `Busy`. The alternate system skips that check and returns the file contents.
// The property verifies that the postcondition catches this mismatch and that
// the recorded history contains the full three-command prefix needed to explain
// the failure.
test "qsm blog filesystem catches missing busy read check" {
  let root = fs_root_dir()
  let a = fs_file(root, "a")
  let commands : Array[FsSymCommand] = [
    FsSymOpen(a),
    FsSymWrite(symbolic_handle(0), "Hi"),
    FsSymRead(a),
  ]
  let result = @quickcheck_statemachine.check(
    fs_script_spec(commands, run_command=run_fs_command_without_busy_check),
    config=case_config(max_commands=commands.length(), shrink=false),
  )
  guard result
    is Err(
      @quickcheck_statemachine.RunFailure::PostconditionFailed(
        step_index~,
        command~,
        response~,
        model~,
        next_model~,
        history~,
        ..
      )
    ) else {
    fail("expected busy read mismatch")
  }
  assert_eq(step_index, 2)
  assert_true(command is FsRead(_))
  assert_true(response is FsSucceeded(FsText("Hi")))
  assert_true(fs_postcondition(model, command, response).eval() == false)
  assert_true(next_model == model)
  assert_eq(@quickcheck_statemachine.make_operations(history).length(), 3)
  assert_eq(model.handles.length(), 1)
  assert_true(model.handles[0].file == a)
}
