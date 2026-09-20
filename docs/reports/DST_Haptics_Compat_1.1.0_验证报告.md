# DST Haptics Compatibility 1.1.0 验证报告

日期：2026-09-20  
DST：Windows x64，build 752666  
安装目录：`C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst_haptics_compat`

## 技术结论

原版 `haptics.lua` 正常加载并注册；Profile 开关、声音事件和 `TheInputProxy:AddVibration` 也分别可工作。失效点位于闭源 `TheHaptics` 的 Windows 设备/波形输出路径，纯 Lua 没有可访问的逐样本播放或后端重绑定接口，无法直接修复该 C++ 路径。

旧版兼容层仅包装客户端 Lua `SoundEmitter`，而砍树、普通采矿命中及大量战斗材质声音由服务器执行后经引擎复制，客户端 Lua 包装器看不到，所以出现“砍树不震、采矿仅最后一下震、打怪反馈固定”的现象。

1.1.0 改为 Hybrid Compatibility Layer：当前 `haptics.lua` 仍是数据源；客户端声音事件走通用捕获；服务器声音缺口通过本地动作上下文、复制状态和原版动作帧桥接；输出统一交给 `TheInputProxy`。

## 控制器路径

- Xbox/XInput：DST 类型 1。
- DualShock 4：DST 类型 2。
- PS5 Controller：DST 类型 7。
- DualSense：DST 类型 11。

四类设备均经过同一个活动设备检查、Profile 总开关、强度/空间/去重和生命周期管理。自动测试确认类型 1/2/7/11 被接受，键鼠类型 0 被拒绝。

纯 Lua 无法发送 DS4/DS5 USB/Bluetooth HID 报告。直连 PlayStation 手柄必须由 DST 或 Steam Input 提供实际马达输出路径；本 Mod 不使用外部桥接程序。当前机器未连接 DS4/DS5，因此无法声称完成这两类硬件的物理体感测试。

## 已验证

- Lua 5.1 语法：全部 Mod 文件通过。
- 当前原版数据：492 条定义全部可建立配置，489 个唯一事件。
- Xbox、DS4、PS5、DualSense 设备类型路由模拟通过。
- Profile 关闭、无控制器、暂停、`player_only`、Boss 远距离、UI 无实体、强度单调、重复事件、循环开始/音量/停止、世界卸载清理通过。
- 砍树第 2 帧、采矿第 7 帧、受伤、饥饿状态和近战材质命中桥接回归通过。
- 原版 WAV 家族测量后，砍树、采矿、挖地、挥动、材质命中使用不同包络；大/中/小目标及钝/利器具有不同倍率。
- 游戏本体前端实际加载 1.1.0 成功；`client_log.txt` 未发现 Lua、LOAD 或 MOD 错误。

## 仍需真实游戏/硬件验收

- 在世界内连续砍树、采矿、近战、受伤、Boss 近远距离、洞穴切换的物理手感。
- DS4 与 DS5 的 USB、Bluetooth、Steam Input 开/关组合。
- 引擎直接复制且客户端没有任何 Lua 动作、动画、HUD 或声音回调的少数服务器事件，纯客户端 Lua 无法通用截获。
- Klei 882 Hz Haptic WAV 的逐采样左右马达波形无法由 `AddVibration` 精确播放，目前使用测量后的多脉冲包络近似。

## 设置与日志

游戏原版“控制器震动”和 Mod“震动适配”必须同时开启。Mod 还提供语言、50%–150% 总体强度和调试日志。调试日志位于：

`%USERPROFILE%\Documents\Klei\DoNotStarveTogetherBetaBranch\client_log.txt`

若 Klei 以后修复原生 Windows Haptics，把 Mod 的“震动适配”关闭；下一次重载时将不注入兼容层，也不抑制原生 `TheHaptics`。
