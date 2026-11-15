# 多智能体开发与维护 / Multi-agent workflow

## 模型选择属于用户

主对话负责需求、长期设计、任务拆分、证据判断、集成和交付。你随时在界面选择主模型、
推理档位和速度；仓库没有主模型、全局 effort 或 service tier 的强制设置。

| 工作 | 建议 | 使用条件 |
|---|---|---|
| 长期设计、原版机制调查、跨模块取舍 | 用户选择的主模型，或独立 Astra 设计审查；high/xhigh，确有需要才 max | 问题有实质不确定性，先给证据和验收标准 |
| 清晰的单项功能或维护 | Sol，通常 high；复杂任务按需 xhigh/max | 输入和文件边界足够明确，独立实现能节省时间 |
| 独立证据/回归审查 | Sol high，通常只读 | 对高风险逻辑提供不同视角，避免重复实现 |
| 小修、简单查询、顺序依赖任务 | 当前主对话直接完成 | 委派成本高于收益时不派 agent |

`astra-max`、`sol-high` 是模型族和推理档位的口语组合，不直接作为 API model ID。
本项目示例使用当前工具提供的 `gpt-6-astra` + `xhigh`、`gpt-6.1-sol` + `high`。
支持列表或账号权限变化时优先实际可用值；不静默切换到更贵配置。

`.codex/config.toml` 只给子 agent 设置 Sol/high 默认与每会话最多两个子任务。
`.codex/agents/` 提供可选的 architect、worker、reviewer 角色。某些宿主不会加载
这些本地配置；此时由主对话发送同样的任务约束，不能假称角色或设置已经生效。
速度档随根会话，角色文件不单独承诺更快服务。

固定角色文件中的model/effort可能优先于spawn参数。你明确指定不同档位时，协调者应
使用通用spawn并显式选择模型/effort，或调整对应预设；不能用固定high预设覆盖你的max要求。

## 两种并行方式

**一个主对话 + 少量子任务**：默认方式。主对话保留决策上下文；只读调查可共享目录，
子任务返回路径、结论和不确定性。可并行写入的功能必须分离到不同 worktree。

**多个独立主对话**：适合你主动开启多个长期功能。每个主对话可以自行选择模型，
拥有一份任务、一条 `codex/<task>` 分支和独立 worktree；它们没有天然共享的会话记忆。
通过任务文件和 Git 提交交接。当前主对话作为集成协调者，除非你明确指定替代者。
每个会话两子任务的配置不是跨会话总量锁；多个主对话开始前须登记活跃任务，
由协调者控制总并发，避免多会话各自展开大量子 agent。

## 委派前的最小合同

采用 [任务模板](../tasks/TEMPLATE.md)，写清：目标、基线提交、输入证据、可写路径、
只读路径、非目标、输出位置、验收命令、主协调者。没有边界时先调查，不开始多方写入。

同一个文件只能有一个活跃写入者。两个任务同时涉及 `haptic_adapter.lua` 时，先把
接口设计定下来，再串行集成；不能假设 Git 自动合并就等于语义兼容。

## 工作树操作

优先使用桌面应用提供的 Worktree 功能。也可以在仓库中执行：

```powershell
git worktree add -b codex/task-a ../dst-haptics-worktrees/task-a main
```

`main` 仅是示例起点；任务必须记录真实基线，后续任务需包含本次维护提交。
先检查 `git worktree list` 和目标路径不存在。新 worktree 只包含已提交内容，
不会自动带入另一个会话的未提交修改、原版脚本、日志或本地配置。

在目标 worktree 显式运行命令；agent 不得切换别人的分支。不要在主 checkout
里运行两个会改 Git 索引/分支的 agent。应用子 agent 默认共享文件系统，
仅写“worker”或“只读”不是操作系统级隔离。

## 集成与验收

1. Worker 提交或交回补丁、完整 diff、验证结果与未测边界；不自行 merge/tag/publish。
2. Reviewer 按风险检查原版语义、生命周期、hook 返回值和证据，不重复实现。
3. 协调者查看差异与依赖顺序，再集成到维护/发布分支。
4. 在集成后的真实源码上运行统一验证，必要时用当前原版快照和实机补充。
5. 完成任务交接、证据索引与状态后，再按已授权流程同步远端。Workshop 更新单独处理。

共享资源（Git refs、release staging、游戏安装、归档目录）始终单写入。
任一任务失败时保留分支/报告，缩小范围；不要无限递归派 agent 或让重试覆盖失败证据。

## 模型切换与上下文恢复

切换主模型前，写好任务状态、关键决策和下一步；切换后读这些文件和 diff 即可。
不依赖“高级模型刚才想过”的隐含记忆，也不复制所有调试输出进每个任务。
必要的设计理由留在架构/任务文档，原始输出留本地证据。

官方参考（2026-11-15 核对）：[Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)、
[AGENTS guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md)、
[Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)、
[Project configuration](https://learn.chatgpt.com/docs/config-file/config-basic)。

English: user controls the coordinator's model and speed. Delegate only bounded,
independent tasks; prefer Sol workers and optional Astra design review. Parallel
writers use separate worktrees and owned paths; one coordinator integrates and verifies.
