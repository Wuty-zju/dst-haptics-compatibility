# DST Haptics Compatibility / 饥荒联机版手柄震动兼容

## 中文

这是一个纯客户端 Mod，用于修复 Windows/XInput 环境下 DST 原版 `TheHaptics` 已注册事件、但没有把震动送到手柄的问题。

- 当前游戏自带的 `scripts/haptics.lua` 是事件、`vibration_intensity`、`player_only` 与 `category` 的唯一数据源；Mod 不复制固定事件清单。
- 只在实际原版 SoundEmitter 事件发生后震动，不监听 A/X 键，也不根据 `ACTIONS.CHOP` 猜测命中。
- 原版“控制器震动”设置仍是最高层总开关。原版关闭时，Mod 不输出。
- 兼容层开启时会关闭原生 `TheHaptics` 输出，防止 Klei 将来修复后出现双重震动；事件表仍由原版提供。
- `player_only` 使用 SoundEmitter 所属实体与本地 `ThePlayer` 的严格身份比较。
- UI/HUD 不做世界距离衰减；PLAYER、DANGER、ENVIRONMENT、BOSS 使用不同的平滑空间范围，并乘以调用时音量。
- `_LP`/loop 事件跟随具名声音生命周期；`KillSound`、`KillAllSounds`、实体失效、暂停、断开手柄或关闭设置都会停止继续输出。

限制：Lua 暴露了 `TheInputProxy:AddVibration`，但没有暴露原版 882 Hz Haptic WAV 的逐采样播放接口，也不能读取马达的物理状态。因此事件语义、触发时机、相对强度、空间、循环与过滤逻辑被保留；原始 WAV 的精确左右马达波形由分层短脉冲包络近似，不能宣称 100% 波形一致。

配置页本身不支持用同一页里刚选择的 Language 动态重建其它选项文本，所以配置标题固定使用中英双语；Language 控制运行时日志语言，并在重新载入 Mod 后生效。

### 安装与使用

本机安装目录：`Don't Starve Together/mods/dst_haptics_compat`。在主菜单“模组”中启用 **DST Haptics Compatibility / 手柄震动兼容**；本机安装过程已把它保存为启用状态。游戏原版“控制器震动”和 Mod 的“震动适配”必须同时开启。关闭“震动适配”后，不安装声音钩子，也不抑制原生 `TheHaptics`。

可配置项：震动适配、语言、总体强度（50%/75%/100%/125%/150%）和调试日志。100% 是按当前原版强度层级校准的默认值。

遇到问题时，把“调试日志”设为开启，复现后查看 `Documents/Klei/DoNotStarveTogetherBetaBranch/client_log.txt`；正式版分支通常是 `Documents/Klei/DoNotStarveTogether/client_log.txt`。日志包含事件、类别、实体、距离、原始/最终强度、持续时间、通道和过滤原因，并有节流保护。

已在 Windows x64、DST build 752666 上完成 Lua 5.1 语法、模拟行为回归和真实游戏前端加载验证。若 Klei 以后修复原生 Windows Haptics，请把“震动适配”设为关闭，即可完整旁路本兼容输出并保留原生实现。

## English

This client-only mod repairs the Windows/XInput case where DST registers native `TheHaptics` events but produces no controller output.

- The installed game's `scripts/haptics.lua` is the sole source of truth for events, `vibration_intensity`, `player_only`, and `category`; there is no copied event list.
- Rumble follows actual SoundEmitter events, never controller buttons or guessed actions.
- DST's Controller Vibration option remains the master switch.
- While compatibility output is enabled, native `TheHaptics` output is disabled to prevent double rumble after a future Klei fix.
- `player_only`, spatial category policies, volume, duplicate suppression, named loops, pause, disconnect, and sound cleanup are handled client-side.

Limitation: Lua exposes `TheInputProxy:AddVibration`, but not sample-level playback of Klei's 882 Hz haptic WAV data or physical motor feedback. Event semantics and relative intensity are preserved; exact waveform shape is approximated with calibrated pulse envelopes.

The DST mod configuration screen cannot dynamically rebuild labels from another option selected on that same page. Labels are therefore bilingual; Language affects runtime logs after the mod is reloaded.

### Installation and operation

Local folder: `Don't Starve Together/mods/dst_haptics_compat`. Enable **DST Haptics Compatibility / 手柄震动兼容** in the Mods screen. The installation performed on this machine has already been persisted as enabled. Both DST's Controller Vibration setting and the mod's Compatibility option must be ON. Turning Compatibility OFF installs no sound hooks and does not suppress native `TheHaptics`.

Options: Compatibility, Language, Overall Strength (50%/75%/100%/125%/150%), and Debug Logging. The default 100% preserves the calibrated ordering of native intensities.

For troubleshooting, enable Debug Logging, reproduce the event, then inspect `Documents/Klei/DoNotStarveTogetherBetaBranch/client_log.txt` (normally `Documents/Klei/DoNotStarveTogether/client_log.txt` on the release branch). Logs include event, category, entity, distance, raw/final intensity, duration, channel, and filter reason with rate limiting.

Validated on Windows x64 with DST build 752666 using Lua 5.1 syntax checks, a behavioral regression harness, and an actual game frontend load. If Klei later repairs native Windows haptics, set Compatibility to OFF to bypass this layer completely and retain native behavior.
