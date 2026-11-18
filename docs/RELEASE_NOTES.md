# DST Haptics Compatibility 1.6.2

切回 Native 后，震动控制权会交还 DST。暂停时申请的校准只会在同一玩家和手柄上恢复一次。断连、关闭游戏震动或切换手柄时会取消。

地面降雨和树下雨声在同一次采样采用最终增益。洞穴降雨现在跟随原版 `intensity`。正在输出的持续声在静音或结束时立即移除。

Returning to Native releases the shared vibration output. Calibration requested during pause follows its original player and controller. Surface and cave rain use the latest native gain at each sample. Muting or stopping a playing loop removes its contribution immediately.

## 验证 / Validation

- 本机 DST 762172 / Steam build 26474873。对照脚本包逐项验证 4,109 个文件。本版逐事件表涵盖 506 条定义、503 个唯一事件、30 个循环包络。
- 本地统一验证 17 项通过，0 失败，0 跳过。包含 25 项 Python 回归、原版定义的 41,492 次倍率断言，以及模拟设备和原版天气调用顺序。新增的两份客户端日志均为工坊 1.5.0。
- All current profiles were exported from the mod's own Lua code. Physical Xbox, DualShock 4 and DualSense acceptance for this version remains open. [Detailed review](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.2/docs/reports/1.6.2-review.md) · [503-event comparison](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.2/docs/audit/DST-Haptics-Event-Audit-1.6.2.csv)

下载附件 `dst_haptics_compat-1.6.2.zip` 与配套校验文件。Steam 订阅的版本取决于工坊作者的单独更新。[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756)
