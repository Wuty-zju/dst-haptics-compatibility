# DST Haptics Compatibility — 本机交付与验证报告

日期：2026-09-20  
游戏：Don't Starve Together Windows x64，build 752666  
安装目录：`C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst_haptics_compat`

## 架构

Hybrid（原版数据源 + Compatibility Layer 输出）。Mod 每次启动动态 `require("haptics")`，把当前游戏的原版事件构建为 O(1) 索引；实际事件仍由 `SoundEmitter.PlaySound` / `PlaySoundWithParams` 触发，最终由可工作的 `TheInputProxy:AddVibration` 输出。兼容层启用时抑制原生 `TheHaptics` 输出，避免未来 Klei 修复后双重震动；关闭兼容层后不安装钩子，也不抑制原生实现。

## 原版检查结论

- 当前 `scripts/haptics.lua`：492 条定义、489 个唯一事件、3 个重复事件；重复事件按原生逐条注册的最终定义语义处理。
- 分类：PLAYER 234、BOSS 167、ENVIRONMENT 53、DANGER 13、UI 22、未指定 3；`player_only` 44 条，`audio=false` 14 条。
- 本机存在 1722 个 882 Hz、单声道、16-bit Haptic WAV。原版事件到具体 WAV 的映射位于封闭的 FMOD FEV/FSB 数据中。
- Lua 能注册和控制 `TheHaptics`，二进制中也包含 XInput 输出路径，但当前 Windows 构建没有把原生 Haptic waveform 实际送到活动 XInput 马达。`TheInputProxy:AddVibration` 则可工作。
- Lua 无法读取马达物理状态，也没有逐采样播放原版 Haptic WAV 的公开接口，因此无法在纯 Lua 中证明 C++ 内部的唯一根因；最合理的边界结论是原生 waveform → Windows XInput 输出衔接失效，而不是事件表、音频事件、驱动或手柄硬件失效。

## 完整保留的语义

- 当前及未来 `haptics.lua` 事件覆盖，不维护固定事件清单。
- `event`、`vibration`、`vibration_intensity`、`audio`、`audio_intensity`、`player_only`、`category` 数据。
- 原版声音事件的真实时机；没有按键或 ACTIONS 钩子。
- 严格 `player_only` 本地实体判断。
- PLAYER、DANGER、ENVIRONMENT、BOSS 的平滑空间衰减；UI/HUD 不做世界空间衰减；调用音量参与缩放。
- 原版强度的单调层级，经总体倍率缩放并限制到 AddVibration 的 0..1 合法范围。
- 具名循环声音的开始、PlayingSound、SetVolume、KillSound、KillAllSounds、实体失效、暂停、断线和 world unload 生命周期。
- 事件 + 实体 GUID + 声音实例名 + 小时间窗去重。
- 原版 Controller Vibration 总开关、Mod 总开关、控制器连接/启用状态。

## 近似部分

原版 Haptic WAV 的精确逐采样波形无法通过当前 Lua API输出。兼容层根据事件类别和语义使用分层短脉冲包络，保留相对强度、节奏类别和持续/循环生命周期，但不宣称与 882 Hz 原始左右马达波形 100% 一致。

## 验证结果

- 五个 Lua 文件全部通过 Lua 5.1 解析。
- 行为回归通过：返回值保留、普通声音快速旁路、严格 player_only、近/远 Boss 衰减、UI 非空间事件、强度单调、重复事件最终定义、同帧去重、Profile OFF、无控制器、暂停、具名 loop、SetVolume=0、KillSound、world unload StopVibration。
- 真实游戏前端加载通过：正常读取 492/489 原版事件；无 `MOD ERROR`、无 `LUA ERROR`。
- 真实 SoundEmitter 烟雾测试通过：前端 `click_mouseover` 与 `click_move` 被兼容层识别；测试时没有连接手柄，因此按设计记录 `no_active_controller` 并不输出震动。
- Mod 已从开发期强制加载切换为正常 Mod 索引启用，再次冷启动仍正常加载。
- 物理体感无法由自动化观察；本机测试已确认的 `TheInputProxy:AddVibration` → Xbox 马达链路作为已知前提使用。

## 配置与运维

- 震动适配：开启/关闭，默认开启。
- 语言：中文/English，默认中文；运行时日志在重新载入后切换。配置页标签因 DST 静态加载限制固定为双语。
- 总体震动强度：50%/75%/100%/125%/150%，默认 100%。
- 调试日志：关闭/开启，默认关闭。

启用或停用：主菜单 → 模组 → DST Haptics Compatibility / 手柄震动兼容。保留 Mod 启用但关闭“震动适配”，即可完整旁路兼容层。原版“控制器震动”必须同时开启。

日志（当前 beta 分支）：`%USERPROFILE%\Documents\Klei\DoNotStarveTogetherBetaBranch\client_log.txt`  
正式分支常规路径：`%USERPROFILE%\Documents\Klei\DoNotStarveTogether\client_log.txt`

若 Klei 后续修复原生 Windows Haptics，将“震动适配”设为关闭；这样不会安装 SoundEmitter 兼容钩子，也不会抑制原生 `TheHaptics`。
