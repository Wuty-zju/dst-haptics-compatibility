# 当前状态 / Current status

更新：2026-11-15（北京时间）。详细来源见[证据索引](maintenance/EVIDENCE.md)。

| 项目 | 状态 |
|---|---|
| PR #1 | 已复审、检查通过并合并；main合并提交e3dd8a4 |
| 本轮开发 | codex/release-1.6.0；模块重构、原版路径审计与中英文文档 |
| GitHub版本 | [1.6.0 发布入口](https://github.com/Wuty-zju/dst-haptics-compatibility/releases/tag/v1.6.0)，发布工作流在最终CI通过后生成成品 |
| Workshop | [项目3805091756](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756)，GitHub发版不会自动更新工坊 |
| 原版基准 | DST762172 / Steam build26474873；Steam官方UpToDateCheck于本日返回up_to_date=true |
| 原版定义 | 506条、503唯一事件；排除注释后406有字面引用、97没有 |
| 自动验证 | 集成17项PASS、27个Lua文件、原版41,492次倍率断言、10项Python回归 |
| 实际游戏记录 | 保留的11月7日日志加载的是1.5.0；1.6本轮未新做游戏加载/完整马达体感验收 |
| 本地安装 | 没有重新安装手工Mod，不影响已订阅副本；旧卸载备份仍保留 |

## 1.6的行为变化

- 动态原版索引不变；索引、设备、空间、声音、循环和动作证明独立成模块。
- 新增14个event的运行侧逐项审计；光束只观察真实loop/bigloop声音句柄，不猜动画。
- 修复雨/冰雹等无_LP循环、同名替换、远距离接近恢复、暂停/停用/断连与重装清理。
- 近战与受击近似分别默认关闭；严格模式不再把未证实的复制信号伪装成原声。
- 旧配置键保留，运行时中英文提示即时切换；配置页固定双语。
- README参考用户ha_ninebot的入口/安装/配置/架构/边界分层，提供直接工坊链接。

## 证据与边界

[1.6触发审计](audit/1.6.0-trigger-paths.md) · [1.6审核](reports/1.6.0-review.md) ·
[硬件矩阵](HARDWARE_MATRIX.md) · [路线图](ROADMAP.md)

当前haptics.lua SHA-256：

```text
e54ee51bd9cf3c0a682375dc5c5962b1e3eaa3307e131fc61c5088d3cc70f5b0
```

原始快照、当前审计和最终验证JSON只保存在本地.local/evidence中。
历史492/489、407/96与1.5.0加载记录仍有原始上下文，不冒充1.6实机通过。
原生Windows输出是否已修复没有重新做物理对照，Native模式可供用户比较。
