# 多智能体开发与维护 / Multi-agent workflow

## 分工与模型选择

主对话负责确定原版语义、证据标准、接口边界和最终交付。主模型、推理档位及速度由用户在界面选择。项目配置只限制每个主对话最多同时使用两个子任务，并为子任务提供 high 推理默认值。

| 任务 | 执行者 | 决策依据 |
|---|---|---|
| 长期规划或跨模块设计 | 当前主对话，必要时邀请最新可用 Astra 独立审阅 | high 或 xhigh 用于设计取舍，复杂且未解决的问题可使用 max |
| 明确的修复、重构或维护 | 最新可用 Sol | 通常 high，跨多个状态或时序边界时由协调者指定 xhigh 或 max |
| 独立复核 | 最新可用 Sol，只读 | 核验缺陷复现、修复边界和验收结果 |
| 单处小修、单一顺序依赖 | 当前主对话 | 直接完成通常比拆分更快 |

**每次派工时确定版本。** 先查看当前会话实际提供的模型列表，按任务选择族，再选该族最高可用版本。使用宿主允许显式设定模型的新任务，同时传入完整 ID、推理档位、精简上下文和文件边界。当前桌面派工工具用 `fork_turns="none"` 传显式模型。已存在的子会话保留原模型，跨版本接续时用提交和交接记录开启新任务。

2026-11-18 的可用列表中，Astra 与 Sol 均有 6.2 版。项目角色文件只保存职责约束，使下一次派工可以直接使用宿主新提供的版本。这也允许同一角色按任务选用不同档位。在另一个宿主上，先确认它支持显式选择子模型。缺少所需模型族时，由主对话继续可做的工作并说明可用性。

多版本并存时，可把实际列表交给仓库的只读选择工具。它按数字比较版本，返回一个确实在输入列表中的完整 ID。以下输入是当日例子。

```text
python tools/agent_models.py sol gpt-6.1-sol gpt-6.2-sol gpt-6-astra gpt-6.2-astra
```

`.codex/agents/` 的 architect、worker、reviewer 可用于对应职责。使用角色的协调者仍要显式选模型。宿主只提供通用子任务时，将对应角色的职责和写入边界带入任务。独立会话的额度和模型可用列表可能不同。[官方子任务配置](https://learn.chatgpt.com/docs/agent-configuration/subagents)

## 一个工作区，多个主对话

1. 在[任务登记](../tasks/README.md)查阅当前文件归属，由一名协调者登记新任务。各主对话可以分别承担规划、维护或审阅，各自选择主模型。跨主对话同时进行的任务合计也应按实际收益控制数量。
2. 记录基线、可写文件、验收方式、证据位置和集成人。只读审查可共享 checkout。并行写入使用独立分支和工作树。同一文件需要两个任务修改时，先明确接口，串行合入。
3. 每个任务从明确的提交创建工作树并在该目录工作。Git 提交之外的原版快照和日志通过登记的只读本地路径使用。其他会话的未提交文件不会随工作树复制。
4. 子任务只交回本分支的提交、复现、验证结果和局限。协调者逐条复核，在集成分支重跑交叉测试。远程合并、发布标签、成品目录和游戏安装由本次集成人依次操作。
5. 切换主模型、主对话或交回任务前更新[交接记录](../tasks/TEMPLATE.md)，留下实际模型、提交、已验证行为、未测边界和已释放的文件归属。

```powershell
git worktree list
git worktree add -b codex/<task> ../dst-haptics-worktrees/<task> <baseline-commit>
```

工作树与现有任务不得重名。协作约定通过分支、路径和提交落实。每会话的并发上限由宿主配置控制，多个主对话之间的写入所有权由任务登记协调。原始证据和发布成品分别存放在[工作区指南](WORKSPACE.md)列出的位置。[官方工作树说明](https://learn.chatgpt.com/docs/environments/git-worktrees)

## English

The user controls each primary chat's model, reasoning effort and speed. Select the newest advertised Astra for an independent design review or Sol for bounded implementation and review. Set the model and effort explicitly on each new assignment. Role files carry instructions and leave model selection to the coordinator. Keep independent writers in separate worktrees. Record ownership, evidence and the baseline before delegating. One coordinator verifies the integrated changes and publishes.
