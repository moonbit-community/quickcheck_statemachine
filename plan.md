# quickcheck-state-machine 重写计划

## 目标

直接重写当前库，使它从轻量在线 runner 变成接近 Haskell
`quickcheck-state-machine` 的 program-based 状态机测试库。

不保留现有 `StateMachineSpec`、`check`、`replay`、`assert_check`、
`assert_replay` API。现有 counter、queue、jug、filesystem 测试全部迁移到新 API。

重写后的核心能力：

- 先生成完整 symbolic command program，再执行。
- 支持 symbolic/concrete reference。
- 支持 mock response 和 concrete response 绑定。
- 支持依赖感知 shrinking。
- 支持 `Logic` 风格的诊断型 precondition/postcondition/invariant。
- 支持 history、pretty failure、持久化 replay。
- 支持 label/coverage 诊断。
- 后续支持 parallel commands 和 linearizability checking。

## 源码依据

本计划基于 Haskell `quickcheck-state-machine` 源码：

- `Test.StateMachine.Types`
  - `StateMachine` 字段：`initModel`、`transition`、`precondition`、`postcondition`、`invariant`、`generator`、`shrinker`、`semantics`、`mock`、`cleanup`
  - `Command` 保存 symbolic command、symbolic response 和 response 绑定变量
  - `Commands` 是完整 command program
- `Types.References`
  - `Var`、`Symbolic`、`Concrete`、`Reference`
- `Types.GenSym`
  - fresh symbolic variable counter
- `Types.Environment`
  - symbolic variable 到 concrete value 的执行环境
- `Sequential`
  - `generateCommands`
  - `runCommands`
  - `shrinkCommands`
  - `shrinkAndValidate`
  - `prettyCommands`
  - command name coverage
- `Parallel`
  - `ParallelCommands`
  - parallel-safe suffix generation
  - parallel execution history
  - `linearise`
- `Logic`
  - 带 counterexample 的谓词语言
- `Labelling`
  - `Event`
  - `execCmds`
  - label classification

参考链接：

- https://hackage.haskell.org/package/quickcheck-state-machine-0.10.3
- https://github.com/stevana/quickcheck-state-machine
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Types.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Sequential.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Parallel.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Types/References.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Types/Environment.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Types/GenSym.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Types/History.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Logic.hs
- https://raw.githubusercontent.com/stevana/quickcheck-state-machine/master/src/Test/StateMachine/Labelling.hs

## 新架构

删除当前轻量 runner，重建为以下模块：

- `logic.mbt`
- `references.mbt`
- `environment.mbt`
- `program.mbt`
- `sequential.mbt`
- `shrinking.mbt`
- `history.mbt`
- `labelling.mbt`
- `parallel.mbt`
- `pretty.mbt`

根包直接导出新 API。旧 API 不留 deprecated shim。

## MoonBit 适配策略

Haskell 版依赖 higher-kinded `cmd r` / `resp r`、rank-2 traversal、`Typeable`
和 `Dynamic`。MoonBit 当前不适合逐字复刻这些机制，所以重写版采用显式回调：

- 用户命令类型分为 symbolic command 和 concrete command。
- 用户响应类型分为 symbolic response 和 concrete response。
- 用户自己定义 concrete value union，例如 `ConcreteValue::Handle(Int)`。
- 库提供 `Var`、`Ref[V]`、`GenSym`、`Environment[V]`。
- 用户提供 command/response 的变量抽取、变量重写、reify、bind 回调。

这会让 spec 比 Haskell 版更显式，但能力边界清楚，且能在 MoonBit 中实现。

## 目标 Public API 草案

```mbt
pub(all) struct Var {
  id : Int
}

pub(all) enum Ref[V] {
  Symbolic(Var)
  Concrete(V)
}

pub(all) struct GenSym {
  mut next : Int
}

pub(all) struct Environment[V] {
  bindings : Map[Var, V]
}

pub(all) struct Command[CSym, RSym] {
  command : CSym
  response : RSym
  vars : Array[Var]
}

pub(all) struct Commands[CSym, RSym] {
  commands : Array[Command[CSym, RSym]]
}

pub(all) struct RunConfig {
  seed : UInt64
  cases : Int
  max_commands : Int
  size : Int
  max_tries : Int
  shrink : Bool
  max_shrinks : Int
  max_shrink_rounds : Int
}

pub struct StateMachine[
  MSym,
  MCon,
  CSym,
  CCon,
  RSym,
  RCon,
  V,
  S,
] {
  init_symbolic_model : () -> MSym
  init_concrete_model : () -> MCon
  init_system : () -> S raise
  generator : (MSym, Int, @splitmix.RandomState) -> CSym?
  mock : (MSym, CSym, GenSym) -> (RSym, GenSym)
  transition_symbolic : (MSym, CSym, RSym) -> MSym
  transition_concrete : (MCon, CCon, RCon) -> MCon
  precondition : (MSym, CSym) -> Logic
  postcondition : (MCon, CCon, RCon) -> Logic
  invariant : (MCon) -> Logic
  shrinker : (MSym, CSym) -> Array[CSym]
  remap_command : (CSym, Map[Var, Var]) -> CSym?
  reify_command : (CSym, Environment[V]) -> Result[CCon, EnvError]
  run_command : (CCon, S) -> RCon raise
  bind_response : (RSym, RCon, Environment[V]) -> Result[Environment[V], BindError]
  cleanup : (MCon, S) -> Unit raise
}

pub fn generate_commands(...) -> Result[Commands[CSym, RSym], GenerationFailure]
pub fn run_commands(...) -> Result[RunReport[...], RunFailure[...]]
pub fn check(...) -> Result[RunReport[...], RunFailure[...]]
pub fn replay(...) -> Result[RunReport[...], RunFailure[...]]
pub fn assert_check(...) -> RunReport[...] raise
pub fn assert_replay(...) -> RunReport[...] raise
```

名称可以沿用 `check/replay/assert_check/assert_replay`，但语义改为新 program-based
API。

## 阶段 1：删除旧实现骨架

改动：

- 删除 `quickcheck_statemachine.mbt` 中当前在线 runner 实现。
- 删除或重写旧 `RunConfig`、`Replay`、`Step`、`StateMachineFailure`、`RunSummary`。
- 保留文件名可以，内容全部替换成新 API 的基础导出。
- 当前测试先允许失败，随后按阶段迁移。

验收：

- `moon check` 在阶段结束时不一定通过；这个阶段是破坏性拆除。
- 需要在分支上一次性推进到阶段 3 后恢复可编译状态。

## 阶段 2：实现 Logic

新增 `logic.mbt`：

- `Logic`
  - `Top`
  - `Bot`
  - `And`
  - `Or`
  - `Implies`
  - `Not`
  - `Boolean`
  - `Annotate`
  - 基础谓词节点
- `Counterexample`
- `LogicValue`
- `Logic::boolean`
- `Logic::eval`
- 组合函数：`logic_and`、`logic_or`、`logic_implies`、`logic_not`
- 注解函数：`Logic::annotate`

验收：

- 测试覆盖逻辑组合和 counterexample 路径。
- precondition/postcondition/invariant 都以 `Logic` 为结果。

## 阶段 3：实现 References、GenSym、Environment

新增 `references.mbt`：

- `Var`
- `Ref[V]`
- `GenSym`
- `GenSym::new`
- `GenSym::fresh`

新增 `environment.mbt`：

- `Environment[V]`
- `Environment::empty`
- `Environment::insert`
- `Environment::lookup`
- `Environment::merge`
- `Environment::contains`
- `EnvError`

验收：

- 单测覆盖 fresh var 单调递增。
- 单测覆盖环境 lookup/insert/merge。

## 阶段 4：实现 Commands 和完整生成

新增 `program.mbt`：

- `Command[CSym, RSym]`
- `Commands[CSym, RSym]`
- `StateMachine[...]`
- `RunConfig`
- `GenerationFailure`

实现：

- `generate_commands`
- 生成时维护 symbolic model 和 `GenSym`。
- 每次生成 command 后：
  - 检查 `precondition`
  - 调用 `mock`
  - 从 symbolic response 中取得 vars
  - 保存 `Command`
  - 用 `transition_symbolic` 更新 model

需要新增回调：

- `response_vars : RSym -> Array[Var]`

如果不想增加字段，也可以要求 `mock` 返回 `(RSym, Array[Var], GenSym)`，减少库对 response 结构的理解。

验收：

- counter 测试迁移到新 `generate_commands + run_commands`。
- `Commands.length` 能反映生成命令数量。
- 生成失败能返回 deadlock 信息和已生成 commands。

## 阶段 5：实现顺序执行

新增 `sequential.mbt`：

- `HistoryEvent`
- `Operation`
- `RunReport`
- `RunFailure`
- `run_commands`
- `check`
- `replay`
- `assert_check`
- `assert_replay`

执行流程：

1. 初始化 concrete model、system、empty environment。
2. 对每条 symbolic command：
   - 用 `reify_command` 转 concrete command。
   - 记录 `Invocation`。
   - 执行 `run_command`。
   - 记录 `Response` 或 `Exception`。
   - 检查 `postcondition`。
   - 用 `bind_response` 把 symbolic response vars 绑定到 concrete response values。
   - 更新 concrete model。
   - 检查 `invariant`。
3. 成功或失败都尝试 cleanup。

验收：

- counter/queue/jug 测试全部迁移。
- 文件系统示例使用 symbolic handle，而不是脚本中硬编码 handle。
- run failure 区分：
  - `GenerationFailed`
  - `ReifyFailed`
  - `ExecutionFailed`
  - `BindFailed`
  - `PostconditionFailed`
  - `InvariantBroken`
  - `CleanupFailed`

## 阶段 6：实现依赖感知 shrinking

新增 `shrinking.mbt`：

- 删除命令 shrink。
- 单命令 shrink。
- `shrink_and_validate`。

核心算法：

1. 从初始 symbolic model、empty scope、fresh GenSym 开始。
2. 对候选 command list 顺序验证。
3. 先用 `remap_command(scope)` 重写 symbolic refs。
4. 如果变量无法重写，候选非法。
5. 检查 precondition。
6. 重新调用 mock，得到新 symbolic response 和新 vars。
7. 用 `old_vars -> new_vars` 扩展 scope。
8. 更新 symbolic model。
9. 返回合法且更小的 candidate commands。

`check` 流程改为：

- 生成 commands。
- 执行。
- 如果失败且 `config.shrink == true`，循环 shrink。
- 最终返回最小失败 commands 和 shrink 统计。

验收：

- counter 42 bug shrink 到最短必要程序。
- 文件系统删除 open 后，依赖该 handle 的 write/read/close 候选被判非法。
- 单命令参数 shrink 生效。

## 阶段 7：实现 History、Pretty、Replay 持久化

新增 `history.mbt`：

- `Pid`
- `HistoryEvent`
- `History`
- `Operation`
- `make_operations`

新增 `pretty.mbt`：

- `format_commands`
- `format_history`
- `format_failure`
- `format_counterexample`

持久化 replay：

- 由于 MoonBit 没有通用 `Read`，由用户提供：
  - `encode_commands`
  - `decode_commands`
- 提供辅助：
  - `save_commands`
  - `load_commands`
  - `run_saved_commands`

验收：

- `assert_check` 输出缩小后的 commands 和 history。
- 能保存失败 commands 并 replay。

## 阶段 8：实现 Labelling 和 Coverage

新增 `labelling.mbt`：

- `Event[Model, Command, Response]`
- `exec_commands`
- `Labeler`
- `classify`
- `collect_labels`
- `command_names`
- `command_names_in_order`
- `cover_command_names`

`RunReport` 增加：

- `labels : Array[String]`
- `command_distribution : Array[(String, Int)]`

配置增加：

- `required_labels : Array[String]`
- `required_command_names : Array[String]`

验收：

- 文件系统示例提供标签：
  - `OpenTwo`
  - `SuccessfulRead`
  - `ClosedHandleWrite`
  - `BusyRead`
- 测试断言这些标签能被生成器覆盖。

## 阶段 9：实现 Parallel Commands 和 Linearization

新增 `parallel.mbt`：

- `ParallelCommands`
- `NParallelCommands`
- `generate_parallel_commands`
- `run_parallel_commands`
- `linearise`

生成策略：

- 先生成 sequential commands。
- 随机切 prefix。
- 用 `parallel_safe` 从剩余 commands 中找 suffix chunk。
- chunk 拆成两个或 N 个线程。

执行策略：

- prefix 顺序执行。
- suffix 并发执行并收集 history。
- 如果 MoonBit 当前后端不适合真实并发，先提供 deterministic interleaving simulator。

线性化：

- 根据 invocation/response history 枚举合法 interleavings。
- 对每个 interleaving 用 sequential model 检查 postcondition。
- 至少一个 interleaving 成立即通过，否则返回 `LinearizationFailed`。

验收：

- mutable reference 并发示例能发现非线性化历史。
- pretty 输出能展示 prefix 和并发分支。

## 阶段 10：重写文档和测试

重写 README：

- 只展示新 API。
- 文件系统 symbolic handle 作为主示例。
- counter/queue/jug 作为补充示例。
- 增加 shrinking、label、replay、parallel 章节。

重写测试：

- `counter_test.mbt`
- `queue_test.mbt`
- `jug_test.mbt`
- `filesystem_test.mbt`
- 新增：
  - `logic_test.mbt`
  - `references_test.mbt`
  - `environment_test.mbt`
  - `shrinking_test.mbt`
  - `labelling_test.mbt`
  - `parallel_test.mbt`

验收：

- `moon info && moon fmt`
- `moon test`
- 审查 `pkg.generated.mbti`，确认 public API 已完全切换到重写后的设计。

## 推荐落地顺序

1. `Logic`
2. `Var / Ref / GenSym / Environment`
3. `Commands / StateMachine / generate_commands`
4. `run_commands / check / replay`
5. 迁移 counter/queue/jug 到新 API
6. symbolic filesystem 示例
7. dependency-aware shrinking
8. pretty failure / persistent replay
9. labelling / coverage
10. parallel / linearization
11. README 和 API 打磨

## 风险

- API 会明显比当前库复杂；这是重写为对等能力库的代价。
- MoonBit 没有 Haskell 的 rank-2 traversal 和 `Dynamic`，必须用显式回调和 concrete value union。
- Shrinking 实现复杂，建议先只做删除 shrink，再做单命令 shrink。
- Parallel 依赖后端并发能力，必要时先做纯 interleaving simulator。
- 破坏性重写期间测试会短时间不可用，应集中完成阶段 1 到阶段 5 后恢复主干可编译。

## 最小完成标准

第一版重写完成至少需要：

- 新 `StateMachine` spec
- `Logic`
- symbolic refs
- environment
- full command generation
- mock response
- sequential `run_commands`
- dependency-aware shrink
- migrated filesystem symbolic handle test
- migrated counter/queue/jug tests
- readable failure report

达到这些后，当前项目才算从轻量 runner 重写成 Haskell `quickcheck-state-machine`
顺序部分的对等实现。
