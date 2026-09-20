# DST Haptics Compatibility 1.2.0 验证报告

日期：2026-09-20  
DST：Windows x64，build 752666  
安装目录：`C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst_haptics_compat`

## 本轮迭代

1.2.0 在 1.1.0 的原版事件与复制动作混合桥接基础上增加：

- Xbox/XInput、DualShock 4、PS5/DualSense 三套输出响应曲线。
- 自动识别与手动强制手柄族，解决 Steam Input 把设备报告成通用/XInput 时无法正确选择的问题。
- 原版细节、柔和、强力三种马达响应；只改变输出曲线，不改变事件与命中时机。
- 工具、战斗、危险、玩家交互、Boss、环境、UI/HUD、循环效果八组独立倍率。
- 世界事件空间范围倍率。
- F8 局内设置入口，以及暂停菜单 `MENU_MISC_2` 手柄入口。
- 设置保存后 0.5 秒内即时应用；局内关闭适配会立即停止输出并恢复原生 `TheHaptics` 开关。

## 原版语义

当前游戏的 `haptics.lua` 仍是事件及字段的 source of truth。Mod 不把控制器按键直接转换成震动。客户端声音事件由通用 SoundEmitter 层捕获；服务器声音缺口由本地动作上下文、复制状态/目标和原版动作帧联合确认。

原版 `vibration_intensity`、`player_only`、category、调用音量、UI/世界空间差异、循环声音生命周期和 Profile 总开关均保留。普通挥动与真正材质命中保持为两类独立事件。

## 控制器模式

- Xbox/XInput：设备类型 1；保持基准时长和幅度。
- DualShock 4：设备类型 2；补偿过短的 Legacy Rumble 脉冲。
- PS5 Controller / DualSense：设备类型 7/11；使用 DualSense Legacy Rumble 时长与响应补偿。
- Generic / Steam Input：自动模式按 XInput 路径处理，也可在局内强制 DS4 或 PS5 模式。

Lua 没有直接发送 DS4/DS5 USB/Bluetooth HID 报告的接口。直连 PlayStation 手柄的物理输出仍需要 DST 或 Steam Input 提供马达通道；Mod 本身不依赖外部 XInput/HID 常驻桥接。

## 自动验证

- 全部 Mod 文件通过 Lua 5.1 语法验证。
- 当前 `haptics.lua`：492 条定义全部可配置，489 个唯一事件。
- 类型 1、2、7、11 接受；键鼠类型 0 拒绝。
- DS4/DS5 自动时长补偿与 PS5 类型 7/11 等价性通过。
- 强制手柄模式、柔和/原版细节响应切换通过。
- 单类别运行时静音与重新启用通过。
- 运行时 Compatibility OFF 停止兼容输出并恢复原生 `TheHaptics`；重新开启后再次抑制原生输出，避免双震。
- Profile OFF、暂停、断连、`player_only`、空间衰减、UI、循环、去重、热插拔和世界卸载清理通过。
- 砍树、采矿、受伤、饥饿与近战材质命中桥接回归通过。
- 局内配置入口、手柄提示、重复界面防护和配置变化即时应用模拟通过。
- DST 本体实际加载 Version 1.2.0 成功，日志没有 Lua、LOAD 或 MOD 错误。

## 仍属于近似或需要硬件验收

- 882 Hz 原版 Haptic WAV 无法由 Lua 逐采样输出，当前按本机资源测量结果转换为多脉冲包络。
- 近战命中使用复制战斗目标、原版命中帧、目标有效性、距离和原版材质解析器联合判断；客户端没有通用的服务器伤害确认事件，因此这部分是严格约束的近似。
- 客户端完全没有 Lua 声音、动作、动画或 HUD 可观察信号的少数服务器事件无法被纯客户端 Lua 通用截获。
- 当前机器没有 DS4/DS5，不能代替相应硬件完成 USB、Bluetooth、Steam Input 开关组合的物理手感确认。

## 局内使用

- 键盘：世界内按 `F8`。
- 手柄：打开暂停菜单，按底部“震动设置”前显示的 `MENU_MISC_2` 对应键。
- 保存后约 0.5 秒生效。
- 原版“控制器震动”仍必须开启。

日志：`%USERPROFILE%\Documents\Klei\DoNotStarveTogetherBetaBranch\client_log.txt`
