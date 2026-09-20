# DST Haptics Compatibility / 饥荒联机版手柄震动兼容

版本 1.2.0，纯客户端 Mod。

## 中文

### 架构

这是一个 Hybrid Compatibility Layer：

1. 启动时读取当前游戏的 `scripts/haptics.lua`，动态建立原版事件索引。事件、`vibration`、`vibration_intensity`、`audio`、`audio_intensity`、`player_only`、`category` 均以本机当前 DST 为准，不复制固定事件表。
2. 包装客户端 `SoundEmitter.PlaySound` 与 `PlaySoundWithParams`，捕获客户端 Lua 真正播放的原版 Haptic 声音事件。
3. DST 专用服务器播放的部分声音由引擎直接复制到客户端，绕过客户端 Lua 函数。对这类缺口，Mod 使用本地动作上下文、服务器复制标签/目标和原版动作帧三重确认，补齐砍树、采矿、锤击、挖地、近战材质命中、本地玩家受伤与饥饿状态；它不监听 A/X 键，也不会仅因按键震动。
4. 最终只把已经存在于当前 `haptics.lua` 的事件交给 `TheInputProxy:AddVibration`。兼容层开启时关闭无输出的原生 `TheHaptics`，防止 Klei 修复后双震。

### 已保留的原版语义

- 动态事件覆盖与未来新增事件的自动接入（只要该事件能在客户端 Lua 观察到）。
- 原版 `vibration_intensity` 的单调强度层级。
- `player_only`、category、调用音量、UI/世界空间差异和 Boss/环境距离衰减。
- 原版攻击挥动与实际材质命中是两类独立事件；挥空是否有挥动震动由当前 `haptics.lua` 决定。
- 具名 `_LP`/loop 声音随 `KillSound`、`KillAllSounds`、实体失效、暂停、世界卸载和手柄断开清理。
- Profile 中“控制器震动”仍是总开关；关闭后兼容层不输出。

服务器复制动作桥的当前帧依据与 build 752666 原版一致：普通砍树第 2 帧，采矿/锤击第 7 帧，挖地第 15 帧；近战按当前 `SGwilson` 的 6/7/8/10 帧分支选择。矿物冰冻、月玻璃/晶体以及蘑菇树、海狸形态均选择对应原版事件。材质命中优先调用游戏自己的 `GetWallImpactSound`、`GetObjectImpactSound`、`GetCreatureImpactSound`。

### Xbox、DS4、DS5

Mod 不调用 Xbox 专属 DLL，而是使用 DST 自己的活动设备与 `TheInputProxy`：

- Xbox / XInput：DST 设备类型 1。
- DualShock 4：设备类型 2。
- PS5 Controller：设备类型 7。
- DualSense：设备类型 11。
- Steam Input 或虚拟控制器也可通过 DST 的通用设备路径工作。

这些类型都会通过同一套事件、强度、空间和生命周期逻辑，不会因不是 Xbox 而被过滤。Lua 没有直接发送 DS4/DS5 USB/Bluetooth HID 马达报告的 API，所以直连 PlayStation 手柄的物理输出仍要求 DST 本身或 Steam Input 向该设备提供震动能力；这是纯 Lua 客户端 Mod 无法越过的引擎边界，不需要也不使用外部常驻桥接程序。

“自动”模式按当前 DST 设备类型选择响应曲线：Xbox 保留标定幅度与时长；DS4 对短脉冲增加最低持续时间并作轻微响应补偿；PS5/DualSense 使用稍长的最短脉冲和 Legacy Rumble 补偿。Steam Input 把设备报告为通用/XInput 时，可以在局内手动强制 DS4 或 PS5 模式。所有模式只改变马达输出曲线，不改变原版事件、帧时机和过滤规则。

### 波形与限制

游戏附带 882 Hz Haptic WAV，但 Lua 没有逐采样播放接口，也无法读取马达物理状态。Mod 已从本机原版 WAV 测量并分别校准砍树、采矿、挖地、攻击挥动和肉体/材质命中的持续时间、衰减与相对幅度；不同目标大小及钝器/利器不再使用同一个固定脉冲。事件语义和相对层级可保留，精确左右马达波形仍属于近似，不能称为 100% 原版波形。

引擎直接复制且客户端没有动作、动画、HUD 或声音 Lua 回调的极少数服务器事件，纯客户端 Lua 无法通用截获。普通客户端声音、UI/HUD、循环效果，以及上述工作、受伤和近战缺口已覆盖；调试日志的 `source` 字段可区分 `sound`、`replicated_work`、`replicated_combat` 与 `replicated_health`。

### 安装与设置

安装目录：`Don't Starve Together/mods/dst_haptics_compat`。

在主菜单“模组”中启用 **DST Haptics Compatibility / 手柄震动兼容**。游戏原版“控制器震动”和 Mod 的“震动适配”必须同时开启。配置项：

- 震动适配：开/关；关闭时不注入任何兼容钩子，也不抑制原生行为。
- 语言：中文/English；配置页固定双语，运行时日志在重新载入后切换。
- 总体强度：50%/75%/100%/125%/150%，默认 100%。
- 手柄震动模式：自动、Xbox/XInput、DualShock 4、PS5/DualSense。
- 马达响应：原版细节、柔和、强力；默认原版细节。
- 独立倍率：工具、战斗、受伤危险、玩家交互、Boss、环境、UI/HUD、持续循环。
- 空间作用范围：75%–150%，只改变世界事件的远端衰减距离。
- 调试日志：默认关闭。

在世界内按 `F8` 可直接打开本 Mod 的原版配置界面。使用手柄时先打开暂停菜单，再按界面底部标出的 `MENU_MISC_2` 对应按键进入“震动设置”。保存后约 0.5 秒内即时生效，不需要退出世界。运行中关闭“震动适配”会立即停止兼容输出并恢复原生 `TheHaptics` 开关状态。

复现问题后查看 `Documents/Klei/DoNotStarveTogetherBetaBranch/client_log.txt`；正式分支通常为 `Documents/Klei/DoNotStarveTogether/client_log.txt`。若 Klei 以后修复原生 Windows Haptics，把“震动适配”设为关闭即可完整旁路本 Mod。

## English

Version 1.2.0 is a client-only hybrid compatibility layer. It dynamically indexes the installed `haptics.lua`, captures real client SoundEmitter events, and bridges server-replicated work, melee-hit, local-health, and hungry-state signals at the original action frames. It never rumbles from an A/X button press alone.

Xbox/XInput (type 1), DualShock 4 (type 2), PS5 Controller (type 7), and DualSense (type 11) all use DST's active-controller abstraction and `TheInputProxy`. Direct DS4/DS5 USB/Bluetooth rumble still requires an output path supplied by DST or Steam Input because Lua cannot send HID motor reports.

Native intensity order, `player_only`, category, volume, spatial attenuation, named-loop lifecycle, pause/disconnect cleanup, and the game's Controller Vibration master setting are preserved. Shipped 882 Hz waveform families were measured to calibrate separate chop, mine, dig, swing, and material-impact pulse envelopes; sample-exact left/right motor playback is not exposed to Lua.

Install at `Don't Starve Together/mods/dst_haptics_compat`, enable the mod, and keep DST Controller Vibration enabled. Press `F8` in-world, or use the `MENU_MISC_2` prompt from the controller pause menu, to open live settings. Controller family, motor response, per-category levels, loop level, spatial reach, language and logging apply without leaving the world. If Klei repairs native Windows haptics, turn Compatibility OFF to bypass this layer entirely.
