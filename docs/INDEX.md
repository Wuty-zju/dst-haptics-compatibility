# 项目导航 / Project index

先读 [STATUS](STATUS.md)。这里把当前事实、维护方法和历史证据分开，避免依赖某一次对话的记忆。

| 目的 | 入口 |
|---|---|
| 当前版本、Workshop、下一步 | [当前状态](STATUS.md) |
| Agent 最小上下文 | [AGENTS.md](../AGENTS.md) |
| 目录、命令、归档与换电脑 | [工作区使用](maintenance/WORKSPACE.md) |
| 模型分工、并行、工作树与验收 | [多智能体协作](maintenance/MULTI_AGENT.md) |
| 证据来源、日期、可信边界 | [证据索引](maintenance/EVIDENCE.md) |
| 当前开发顺序 | [路线图](ROADMAP.md) |
| 任务登记与交接 | [任务目录](tasks/README.md) · [模板](tasks/TEMPLATE.md) |
| 原版语义与兼容层设计 | [架构](ARCHITECTURE.md) |
| 自动验证、原版数据与实机验收 | [测试](TESTING.md) · [硬件矩阵](HARDWARE_MATRIX.md) |
| 发布与另一台电脑更新 | [Steam Workshop](STEAM_WORKSHOP.md) · [页面文案](WORKSHOP_DESCRIPTION.md) |

## 历史材料 / History

- [变更记录](../CHANGELOG.md) 与 [1.5.0 发布说明](RELEASE_NOTES.md)。发布标签的文件保持原样。
- [1.4.0 计划](PLAN-1.4.0.md)、[1.5.0 计划](PLAN-1.5.0.md) 和 [1.5.0 开发过程](notes/1.5.0-progress.md)：按当时日期理解，末尾状态优先于中间检查点。
- [1.5.0 审核](reports/1.5.0-review.md) 和 [发布凭证](reports/1.5.0-release-receipt.md)。凭证是历史记录，不自动成为今天的复测结果。
- [1.4.0 审计摘要](audit/DST-Haptics-Audit-Summary-1.4.0.md) 与 [逐事件 CSV](audit/DST-Haptics-Event-Audit-1.4.0.csv)：492 条定义、489 个唯一事件的旧快照。
- 更早的报告保留在 `docs/reports/`，更早的审计保留在 `docs/audit/`。临时副本和旧二进制移到本地忽略的 `archive/`，不重写历史报告。

English: read STATUS first, use the evidence index for provenance, and keep historical
reports separate from current automated and physical acceptance. Repository guidance
and task handoffs are versioned; raw game data and logs remain local.
