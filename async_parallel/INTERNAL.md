# async_parallel Internal Design

本文档面向维护者，说明 `async_parallel` 包的设计目标、主要算法和当前实现边
界。外部用户文档见 `README.mbt.md`。

## 设计目标

`async_parallel` 沿用根包 `quickcheck_statemachine` 的模型、命令、环境、
历史和报告类型，并在这些类型之上增加真正的异步并行执行路径。

核心约束如下：

- 复用根包的 `StateMachine` 心智模型，降低同步规格迁移成本；
- 只让触达被测系统的回调异步化，保持生成和模型检查的确定性；
- 保持 `RunReport`、`ParallelCommands`、`Commands`、`History`、
  `Environment` 等公共数据结构一致；
- 不修改根包同步 `RunFailure` 的枚举，异步并行专属失败单独放入
  `AsyncRunFailure`；
- 线性化搜索必须有较小且明确的预算，避免并发后缀稍大时产生不可控的阶乘搜索。

当前实现是二分支并行：一个顺序 prefix，加上 left/right 两个并发 suffix。

## 文件分工

- `async_program.mbt` 定义公共规格类型 `AsyncStateMachine`，以及
  `AsyncStateMachine::new` 和 `AsyncStateMachine::from_sync`；
- `async_failure.mbt` 定义 `AsyncRunFailure`，并提供把同步 `RunFailure`
  包装进 async 失败的内部 helper；
- `async_parallel.mbt` 实现生成、并行执行、环境合并、线性化、覆盖率报告和
  顶层入口；
- `*_wbtest.mbt` 覆盖内部生成和线性化细节；
- `*_test.mbt` 覆盖外部 API 行为。

## AsyncStateMachine 的形状

`AsyncStateMachine` 基本镜像根包的 `StateMachine`。差异只有：

- `init_system : async () -> S`
- `run_command : async (CCon, S) -> RCon`
- `cleanup : async (MCon, S) -> Unit`

其他回调保持同步、纯粹和确定。生成阶段不应触达真实系统，也不应受到异步调度
影响。`from_sync` 把同步回调包成 async 形状。它不会让同步命令内部自动产生
调度点。

`AsyncStateMachine::new` 的默认值与根包 `StateMachine::new` 对齐：可选逻辑
默认为 `Logic::top()`，`response_vars`、`shrinker` 和 `label` 默认为空，
`remap_command` 默认 identity，`cleanup` 默认 no-op，`command_name` 默认
`"command"`。

## 生成流程

生成入口是内部函数 `generate_parallel_commands_async_spec`：

1. `generate_commands_with_seed_async_spec` 从 `init_symbolic_model` 开始生成
   一个顺序 `Commands`；
2. 每一步在当前模型上调用 `generator(model, config.size, rng)`；如果候选命令
   被 `precondition` 拒绝，同一个 step 会继续重试，最多重试
   `config.max_tries` 次；
3. 任一次尝试返回 `None` 都表示自然停止，不会继续消耗剩余 retry 预算；
4. 对 `Some(command)` 先检查 `precondition`；
5. 如果连续 `config.max_tries` 个 `Some(command)` 都被 `precondition` 拒绝，
   则返回 `Deadlock`；
6. `mock` 产生符号响应并推进 `GenSym`；
7. `response_vars` 写入 `Command.vars`；
8. `transition_symbolic` 推进符号模型。

生成完成后，`split_parallel_commands_after_generation_async` 将顺序程序拆成
并行形状：

- `prefix_len = len / 2`；
- prefix 之后从左到右尝试选择最多 `max_parallel_operations()` 个命令作为并
  发 chunk；
- chunk 通过 `commands_are_parallel_safe` 逐个扩张；第一个不安全候选会终
  止扩张，不继续扫描后续候选；
- chunk 的前半部分成为 left，后半部分成为 right；chunk 长度为奇数时，
  left 取 `chunk.length() / 2` 个命令，right 取得剩余命令；
- chunk 之后的顺序命令当前会被丢弃，不会形成 tail。

`max_parallel_operations()` 当前返回 6。这个值同时约束生成出来的并发 chunk
和手工传入命令的线性化预算。

## 并发安全筛选

`commands_are_parallel_safe` 避免生成出明显不适合放进并发 chunk 的命令。
它只做生成阶段的保守过滤，不提供最终正确性证明。

检查包含两层：

1. 对 chunk 中每个命令调用 `remap_command(command.command, prefix_scope)`。
   这里的 scope 只包含 prefix 已经产生的变量，并通过 `extend_identity_scope`
   构造；检查过程中不会把 chunk 自己产生的新变量加入 scope。变量依赖检测
   取决于规格提供的 `remap_command`：如果命令依赖 chunk 内部先前命令产生
   的新变量，正确实现的 `remap_command` 会因为 scope 缺失返回 `None`，该候选
   会被排除在并发 chunk 外。默认 identity `remap_command` 不会自行检查命令里
   的变量引用。`remap_command` 的结果只用于判断是否为 `Some`，不会改写保存在
   chunk 中的命令。
2. 枚举 chunk 的所有排列。每个排列都从新的 `GenSym::new()` 开始模拟，并且
   必须满足：
   - 当前模型下 `precondition` 为真；
   - 用当前模型和排列模拟中的当前 `GenSym` 调用 `mock` 后，
     `response_vars(mock_response)` 的数量等于原命令记录的
     `vars.length()`；
   - `transition_symbolic` 能用原命令记录的符号响应依次推进模型。

排列检查不要求重新调用 `mock` 得到的响应与原命令记录的响应相等。它只验证
这个排列下的前置条件、变量数量和符号模型推进是否仍然自洽；新模拟出来的响应
不会替换原命令中保存的符号响应或变量。

枚举所有排列会增长很快。chunk 上限是 6，检查规模可控。这样做的直接收益是：
生成阶段不会把有顺序依赖的命令硬塞进并发后缀；真正的语义错误仍然交给运行
阶段和线性化阶段报告。

## 执行流程

公共入口 `run_parallel_commands_async` 的高层流程如下：

1. 校验 `RunConfig` 中的非负和正数约束；
2. 把 `ParallelCommands` 扁平化为 `all_commands`，用于报告和失败上下文；
3. 检查 `left.length() + right.length()` 是否超过
   `max_parallel_operations()`，超过时立即返回
   `LinearizationBudgetExceeded`，不会调用 `init_system`；
4. 调用 `init_system` 创建本 case 的系统；
5. 通过 `run_prefix_async` 顺序执行 prefix；
6. 用 `@async.with_task_group` 同时启动 left 和 right；
7. 两个分支共享同一个 `system`，各自使用 prefix 环境的副本；
8. 等待两个分支结束并收集 prefix 历史与并发历史；
9. 检查分支结果；任一分支失败时转为 `ReplayFailed`；两个分支都失败时，当前
   匹配顺序优先报告 left 失败；
10. 两个分支都成功后，合并分支环境增量；
11. 对并发历史执行线性化搜索；
12. 成功后调用 `cleanup`，再做覆盖率检查并构造 `RunReport`。

`run_prefix_async` 基本是根包 `run_commands` 的 prefix 子集：reify、记录
invocation、执行命令、记录 response 或 exception、计算 next model、用执行
前模型检查 postcondition、bind response、检查 invariant、收集 label。prefix
失败时返回 `AsyncReplayFailure`，其中保存原始 `RunFailure` 和用于 cleanup
的模型。

`run_branch_async` 只负责单分支执行和环境推进。它不检查 postcondition 或
invariant，因为并发分支的合法性要在线性化阶段按某个全局顺序判断。分支内部
会在 reify 成功后记录 invocation；执行成功时记录 response，执行抛错时记录
exception；bind 失败发生在 response 已记录之后。reify、execution、bind 失败
都会归约为内部 `BranchFailure`。

## 历史模型

历史使用根包 `History[CCon, RCon]` 和 `HistoryEvent`：

- prefix 中成功执行的每个命令是严格相邻的 `Invocation` 和 `Response`；
- prefix 或分支执行阶段抛错时，已经记录的调用会以相邻或后续的 `Exception`
  作为终止事件；reify 失败不会产生 invocation；bind 失败不会新增
  `Exception`，此前记录的 `Response` 会保留；
- 并发分支把事件 push 到同一个 `concurrent_events` 数组；
- `Pid` 分配遵循扁平命令顺序：prefix、left、right；
- `full_history = prefix_state.history + concurrent_events`。

`run_command` 抛出的错误会被捕获并转换成字符串，历史中记录 `Exception`。分
支异常随后通过 `branch_failure_to_run_failure` 转换成根包的
`ExecutionFailed`。分支 bind 失败同样会在进入线性化前转成
`ReplayFailed(... BindFailed ...)`。正常进入线性化阶段的并发历史只包含成功分
支产生的 `Invocation` 和 `Response`。

## 环境隔离与合并

prefix 执行完成后得到基础 `Environment[V]`。left 和 right 都从
`copy_environment(base)` 开始运行。两个分支不能通过环境看到彼此新创建的
变量。

分支成功后：

1. `environment_delta(base, branch_env)` 只取基础环境中不存在的新绑定；
2. 先把 left delta merge 到 base；
3. 再把 right delta merge 到上一步结果；
4. 如果 merge 发现重复变量，返回 `BranchEnvironmentMergeFailed`。

delta 会过滤掉 base 已有变量。根包 `Environment::insert` 本身允许覆盖已有
绑定。当前实现实际检测的是 left/right 两个分支之间的新绑定冲突；它不会把分
支覆盖 prefix 已有变量识别为 merge 冲突。规格的 `bind_response` 应避免覆盖
已有变量。merge 后的环境不会继续用于后续命令，并行程序在 right 之后没有
tail。未来如果扩展为 prefix + suffixes + tail，需要保留并传递合并后的环境。

## 线性化算法

线性化入口是 `linearise_history(spec, start_model, history, max_operations)`。

它首先用 `count_invocations` 统计并发历史中的操作数量。超过预算时返回
`BudgetExceeded`。预算内调用 DFS：

1. 如果事件为空，说明所有操作都已选择，返回最终模型和标签；
2. `opening_invocation_count` 找到历史开头连续的 invocation 数量；
3. DFS 只能从这些 opening invocation 中选候选操作；
4. 对候选 `Pid` 查找后续匹配 response；
5. 用当前模型执行 `postcondition`；
6. 通过 `transition_concrete` 得到下一模型；
7. 检查 `invariant`；
8. 移除 invocation/response 这一对事件，递归处理剩余事件；
9. 如果所有候选都失败，把失败 logic 聚合为 `NotLinearizable`。

只允许选择 opening invocation 是维护实时顺序的关键：一旦历史中出现 response
或 exception，后续才 invocation 的操作就不能被移动到它之前。DFS 搜索所有
遵守 invocation/response 偏序的顺序解释。

当前 DFS 只把正常 `Response` 作为可线性化事件处理。出现 `Exception` 的分支
会在进入线性化前被转换为 `ReplayFailed(... ExecutionFailed ...)`。正常的线
性化输入不应包含 exception。

## 覆盖率与报告

成功线性化后：

- 先用线性化结果中的最终模型调用 `cleanup`；
- cleanup 成功后合并 prefix labels 和 parallel labels；
- `collect_labels` 去重；
- `command_names(all_commands, spec.command_name)` 生成命令分布；
- `missing_required_values` 检查 `required_labels`；
- `cover_command_names` 检查 `required_command_names`；
- 覆盖率缺失时包装为 `ReplayFailed(... CoverageFailed ...)`。

`check_parallel_async` 多 case 成功时返回的 `RunReport` 汇总
`cases_run` 和 `commands_run`。`commands`、`history`、`labels` 和
`command_distribution` 来自最后一个 case。这个风格与根包 `check` 一致。
当 `config.cases == 0` 时，它返回空命令、空历史、空标签和空命令分布。

## 失败分层

`AsyncRunFailure` 是外层枚举，用于避免扩大根包 `RunFailure`。

`ReplayFailed` 包装所有可以自然表达为根包 `RunFailure` 的失败：

- `InvalidConfig`
- `GenerationFailed`
- `InitFailed`
- `ReifyFailed`
- `ExecutionFailed`
- `BindFailed`
- `PostconditionFailed`
- `InvariantBroken`
- `CleanupFailed`
- `CoverageFailed`

异步并行专属失败单独建模：

- `LinearizationFailed`：执行都成功，历史不可线性化；
- `LinearizationBudgetExceeded`：并发操作数超过预算；
- `BranchEnvironmentMergeFailed`：两个分支的环境增量冲突。

系统已经成功创建后的失败路径会通过 `async_cleanup_after_failure` 执行
cleanup，并吞掉 cleanup 本身的错误，以免掩盖原始失败。配置错误、生成失败和
`init_system` 失败发生在没有可清理系统或没有已初始化系统的阶段，不会调用
cleanup。公开入口的并发预算预检也发生在 `init_system` 前。`linearise_history`
内部仍保留防御性的 `BudgetExceeded` 返回分支。当前公开入口已经用
`left.length() + right.length()` 做过同一预算预检，正常不会在系统创建后再次
触发。如果未来复用线性化函数或历史构造变化导致该分支触发，会按普通失败
路径执行 cleanup。成功路径上的 cleanup 错误会报告为
`CleanupFailed`。覆盖率失败发生在成功 cleanup 之后，不会再触发失败路径
cleanup。

## 当前边界

- 只支持二分支 `ParallelCommands`，未支持 `NParallelCommands`；
- 并发 suffix 操作预算固定为 6；
- `check_parallel_async` 当前不执行 shrink；
- 生成器的并发切分策略是保守启发式，不保证最大化并发覆盖；
- 线性化搜索是 DFS，没有 memoization；
- 并发阶段之后没有 tail，合并后的环境没有继续被消费；
- 真正的交错依赖 MoonBit cooperative async 调度点。没有挂起点的命令会按原
  子片段执行。

这些边界是有意保守选择。先保证 API 形状、失败上下文和历史语义稳定，再逐步
扩展更复杂的并发生成、shrink 和多分支搜索。
