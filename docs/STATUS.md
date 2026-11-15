# 当前状态 / Current status

更新：2026-11-15（北京时间）。这是维护入口；详细证据见 [索引](maintenance/EVIDENCE.md)。

## 发布与安装

| 项目 | 已核实状态 |
|---|---|
| 最新 GitHub Release | [v1.5.0](https://github.com/Wuty-zju/dst-haptics-compatibility/releases/tag/v1.5.0)，提交 `cd4f1a281e58b33ef155bd6a0bf82e53c1521a0a` |
| 发布包 | ZIP 37,400 字节；本地 SHA-256 与 GitHub Release API 的 digest 一致，见证据索引 |
| Workshop ID | `3805091756`，来自现存 2026-11-07 客户端日志与本机 Workshop 内容目录 |
| Workshop 页面 | [打开项目](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756)；本次未能从网页核实公开可见性、作者和页面元数据 |
| 游戏实际加载 | 11 月 7 日日志：1.5.0，506 条定义 / 503 个唯一事件，初始化成功；不是今天重新启动游戏的结果 |
| 手工本地安装 | 已于 9 月 20 日移出游戏；11 月 15 日检查未发现 `mods/dst_haptics_compat`，保留外部可恢复备份 |
| 本次维护 | 维护分支 `codex/workspace-maintenance`；不升 Mod 版本、不改震动运行时、不安装或上传 Workshop |

## 当前原版基准

当前本机 DST version `762172`，Steam build `26474873`。11 月 15 日从安装目录
`scripts.zip` 提取到独立本地证据目录，得到 **506 条定义、503 个唯一事件**。
9 月基准为 **492 / 489**，不可继续把旧数字写成当前覆盖率。

当前 `haptics.lua` SHA-256：

```text
e54ee51bd9cf3c0a682375dc5c5962b1e3eaa3307e131fc61c5088d3cc70f5b0
```

物理 Xbox、DS4、DS5 的 USB/蓝牙/Steam Input 完整验收仍未完成。设备枚举、
自动测试与游戏加载都不能证明马达体感。现有 Lua 接口也不能证明逐采样原生波形一致。

## 下一轮工作

1. 已完成当前原版表差异与静态引用快照；下一步复审新增事件、受击、Boss 和动作桥的客户端可观察调用路径。
2. 补充最短但真实的手柄验收与世界退出/切洞穴/断连证据。
3. 有证据支持后再改运行时、准备下一个 release；沿用现有 Workshop ID 更新。

执行顺序和并行边界见 [路线图](ROADMAP.md)。本次自动验证结果与归档清单由
[工作区报告](reports/2026-11-15-workspace-review.md)记录。

English: latest release is 1.5.0. A retained November 7 log proves Workshop item
3805091756 loaded; public visibility and physical controller acceptance are not verified.
The November 15 installed native snapshot has 506 definitions / 503 unique events.
