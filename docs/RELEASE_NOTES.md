# DST Haptics Compatibility 1.6.3

无缝换角色或切回兼容模式时，仍在播放的雨声等具名声音可继续震动。打火机等特效移除后，已排队的尾段只有在仍有有效来源时才播放。暂停、换手柄或设置变化后，去重与当前输出同步。

Live named sounds can resume after seamless player swaps and mode changes. Delayed loop segments require a surviving source. Resuming output uses fresh deduplication after a pause, device change or settings change.

## 验证 / Validation

- 本机 DST 762172 / Steam build 26474873，全量核对游戏包的 4,109 个文件。当前数据有 506 条定义、503 个唯一事件。
- 本机 Lua 5.1 回放验证雨声句柄、玩家切换、Boss/设备边界和模拟马达调用。全套 17 项通过，0 失败，0 跳过。最新客户端日志仍记录工坊 1.5.0。
- The package uses tracked runtime Lua from the release checkout. CI compares the exact file list and verifies rebuild hashes after a source timestamp change. Physical Xbox, DualShock 4 and DualSense acceptance remains open. [Review and test evidence](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.3/docs/reports/1.6.3-review.md)

下载具名 ZIP 和配套 `.sha256` 文件。Steam 工坊的更新由项目上传者单独发布。[Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756)
