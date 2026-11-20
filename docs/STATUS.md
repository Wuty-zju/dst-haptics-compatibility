# 当前状态 / Current status

更新于 2026-11-21。[1.6.3 已发布](https://github.com/Wuty-zju/dst-haptics-compatibility/releases/tag/v1.6.3)，标签 dbf9488。线上三个附件已重新下载并校验。[发布凭证](reports/1.6.3-release-receipt.md) · [详细审查](reports/1.6.3-review.md)

| 项目 | 核对结果 |
|---|---|
| 游戏脚本 | DST 762172 / Steam build 26474873。4,109 个文件与保存的快照逐字节相同 |
| 原版事件 | 506 条定义，503 个唯一事件。404 个有静态字面引用，99 个没有。原版字段与包络见 [503 行对照表](audit/DST-Haptics-Event-Audit-1.6.2.csv) |
| 源码验证 | 17 PASS / 0 FAIL / 0 SKIP，25 项 Python 回归，41,492 次原版倍率断言 |
| 本地日志 | 最新日志仍为 11 月 18 日凌晨的工坊 1.5.0。两份有效日志样本有 14 次加载。订阅目录也显示 1.5.0 |
| 工作区 | 三条修复分支分别复核，保留历史工作树和正式成品。当前主对话连接同仓库的 coordinator 工作树 |
| 工坊 | [Steam 项目 3805091756](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756) |

- [本轮任务合同](tasks/2026-11-21-release-1.6.3.md) · [证据索引](maintenance/EVIDENCE.md) · [实机验收矩阵](HARDWARE_MATRIX.md)
- [1.6.2 发布凭证](reports/1.6.2-release-receipt.md) · [1.6.1 发布凭证](reports/1.6.1-release-receipt.md) · [1.6.0 发布凭证](reports/1.6.0-release-receipt.md)
