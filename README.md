# DST Haptics Compatibility / 饥荒联机版手柄震动兼容

版本 1.3.0，纯客户端 Mod。

[完整 489 事件审计表](docs/audit/DST-Haptics-Event-Audit-1.3.0.csv) · [审计摘要](docs/audit/DST-Haptics-Audit-Summary-1.3.0.md) · [架构说明](docs/ARCHITECTURE.md) · [测试方法](docs/TESTING.md) · [更新日志](CHANGELOG.md)

## 中文

### 架构

这是一个 Hybrid Compatibility Layer：

1. 启动时读取当前游戏的 `scripts/haptics.lua`，动态建立原版事件索引。事件、`vibration`、`vibration_intensity`、`audio`、`audio_intensity`、`player_only`、`category` 均以本机当前 DST 为准，不复制固定事件表。
2. 包装客户端 `SoundEmitter.PlaySound` 与 `PlaySoundWithParams`，捕获客户端 Lua 真正播放的原版 Haptic 声音事件。
3. DST 专用服务器播放的部分声音由引擎直接复制到客户端，绕过客户端 Lua 函数。对可证明的缺口，Mod 捕获本地原版动作上下文，并等待 `player_classified.performaction` 或 `attacked` 的服务器回传后再桥接砍树、采矿、锤击、挖地、近战材质命中及本地玩家受击；它不监听 A/X 键，也不会仅因动作动画开始而震动。原版 `audio=false` 的饥饿事件使用本地 hungry 动画进入沿。
4. 最终只把已经存在于当前 `haptics.lua` 的事件交给 `TheInputProxy:AddVibration`。兼容层开启时关闭无输出的原生 `TheHaptics`，防止 Klei 修复后双震。

### 已保留的原版语义

- 动态事件覆盖与未来新增事件的自动接入（只要该事件能在客户端 Lua 观察到）。
- 原版 `vibration_intensity` 的单调强度层级。
- `player_only`、category、调用音量、UI/世界空间差异和 Boss/环境距离衰减。
- 原版攻击挥动与实际材质命中是两类独立事件；挥空是否有挥动震动由当前 `haptics.lua` 决定。
- 具名 `_LP`/loop 声音随 `KillSound`、`KillAllSounds`、实体失效、暂停、世界卸载和手柄断开清理。
- Profile 中“控制器震动”仍是总开关；关闭后兼容层不输出。

工作和近战桥接不再用固定动画帧猜测成功。它等待原版 `player_classified` 的服务器动作结果回传，因此被取消、被服务器拒绝或失效的工作动作不会震。矿物冰冻、月玻璃/晶体以及蘑菇树、石树、海狸形态均选择对应原版事件。近战还复刻 release 版 `combat_replica:CanHitTarget` 的 3D 距离和 0.5 预测容差；材质命中优先按原版护甲优先级，再调用游戏自己的 `GetWallImpactSound`、`GetObjectImpactSound`、`GetCreatureImpactSound`。挥动声仍独立遵循原版，因此严格原版模式下挥空可能有 whoosh，但不会凭空产生材质 impact。

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

游戏附带 1722 个 882 Hz Haptic WAV，但 Lua 没有逐采样播放接口，也无法读取马达物理状态。Mod 已从本机原版 WAV 计算 RMS 包络，分别用于树/蘑菇树砍击、普通/冰/月玻璃采矿、挖地、攻击挥动、肉体/材质命中、饥饿、寒冷和过热；不同目标大小及钝器/利器不再使用同一个固定脉冲。其它事件根据原版 event 语义选择 UI、脚步、重击、爆炸、咆哮、危险、Boss 或环境包络。事件语义和相对层级可保留，精确左右马达逐采样波形仍属于近似，不能称为 100% 原版波形。

引擎直接复制且客户端没有动作、HUD 或声音 Lua 回调的服务器一发事件，纯客户端 Lua 无法通用截获，也不能可靠读取“当前物理马达是否已震”。Mod 不会用“看到某个 Boss 动画就猜一下”的方式制造误震。普通客户端声音、UI/HUD、可见循环效果，以及上述服务器确认的工作、受击和近战缺口已覆盖；调试日志的 `source` 字段会显示 `sound`、`server_confirmed_work`、`server_confirmed_combat`、`server_confirmed_attacked` 或 `replicated_player_state`。

### 安装与设置

安装目录：`Don't Starve Together/mods/dst_haptics_compat`。

在主菜单“模组”中启用 **DST Haptics Compatibility / 手柄震动兼容**。游戏原版“控制器震动”和 Mod 的“震动适配”必须同时开启。配置项：

- 震动适配：开/关；关闭时已安装钩子完整旁路、不输出兼容震动，并恢复原生 `TheHaptics`。
- 语言：中文/English；配置页固定双语，运行时日志在重新载入后切换。
- 总体强度：50%/75%/100%/125%/150%，默认 100%。
- 手柄震动模式：自动、Xbox/XInput、DualShock 4、PS5/DualSense。
- 马达响应：原版细节、柔和、强力；默认原版细节。
- 独立倍率：工具、战斗、受伤危险、玩家交互、Boss、环境、UI/HUD、持续循环。
- 空间作用范围：75%–150%，只改变世界事件的远端衰减距离。
- 调试日志：默认关闭。

在世界内按 `F8` 可直接打开本 Mod 的原版配置界面。使用手柄时先打开暂停菜单，再按界面底部标出的 `MENU_MISC_2` 对应按键进入“震动设置”。保存后约 0.5 秒内即时生效，不需要退出世界。运行中关闭“震动适配”会立即停止兼容输出并恢复原生 `TheHaptics` 开关状态。

复现问题后查看 `Documents/Klei/DoNotStarveTogetherBetaBranch/client_log.txt`；正式分支通常为 `Documents/Klei/DoNotStarveTogether/client_log.txt`。若 Klei 以后修复原生 Windows Haptics，把“震动适配”设为关闭即可完整旁路本 Mod。

### 原版事件全量结果

本机 build 752666 的原版表有 492 条定义、489 个唯一 event：PLAYER 232、BOSS 166、ENVIRONMENT 53、DANGER 13、UI 22、未指定 3。390 个唯一 event 在解包 Lua 中找到字面触发证据；其余 99 个仍进入动态索引，但不凭空构造触发。每一项的原版字段、调用文件/行号、当前捕获路径、正常交互保护、空间逻辑、实际包络与限制均列在 [完整 CSV](docs/audit/DST-Haptics-Event-Audit-1.3.0.csv)。

这张表用于区分三种不同的“覆盖”：客户端可见原声事件可精确桥接；工作/受击/近战等有服务器复制证明的缺口可受约束桥接；完全绕过客户端 Lua 的服务器一发事件只能条件覆盖。把最后一种标成“完整支持”会掩盖纯客户端 API 边界，因此项目不会这样做。

### 手动安装

1. 从 Releases 下载对应版本 ZIP。
2. 解压后确保路径为 `Don't Starve Together/mods/dst_haptics_compat/modinfo.lua`，不要多套一层目录。
3. 主菜单 → 模组，启用 **DST Haptics Compatibility / 手柄震动兼容**。
4. 原版设置中的 **Controller Vibration / 控制器震动** 必须保持开启。

仓库本身也可直接克隆为 `mods/dst_haptics_compat`。本 Mod 是 `client_only_mod = true`，服务器与其它玩家无需安装。

### 开发与审计

仓库不分发 Klei 原始 Lua 或 Haptic WAV。`tools/` 中的审计器接受本机当前脚本和资源路径，`tests/` 使用 DST 兼容 Lua 5.1 运行行为回归。复现命令与物理验收清单见 [测试文档](docs/TESTING.md)。历史版本源码通过 Git tag `v1.0.0`–`v1.3.0` 保留，成品与报告在 GitHub Releases 中提供。

## English

Version 1.3.0 is a client-only hybrid compatibility layer. It dynamically indexes the installed `haptics.lua`, captures real client SoundEmitter events, and waits for server-confirmed `performaction`/`attacked` replication before bridging work, melee impact and local hurt gaps. Hungry uses the original audio-free animation edge. It never rumbles from an A/X button press or an unconfirmed action animation alone.

Xbox/XInput (type 1), DualShock 4 (type 2), PS5 Controller (type 7), and DualSense (type 11) all use DST's active-controller abstraction and `TheInputProxy`. Direct DS4/DS5 USB/Bluetooth rumble still requires an output path supplied by DST or Steam Input because Lua cannot send HID motor reports.

Native intensity order, `player_only`, category, volume, spatial attenuation, named-loop lifecycle, pause/disconnect cleanup, and the game's Controller Vibration master setting are preserved. Shipped 882 Hz waveform families were measured to calibrate separate chop, mine, dig, swing, material-impact, hunger, freeze and heat pulse envelopes; sample-exact left/right motor playback is not exposed to Lua.

Install at `Don't Starve Together/mods/dst_haptics_compat`, enable the mod, and keep DST Controller Vibration enabled. Press `F8` in-world, or use the `MENU_MISC_2` prompt from the controller pause menu, to open live settings. Controller family, motor response, per-category levels, loop level, spatial reach, language and logging apply without leaving the world. If Klei repairs native Windows haptics, turn Compatibility OFF to bypass this layer entirely.

The audited build contains 492 definitions / 489 unique events. The [full event matrix](docs/audit/DST-Haptics-Event-Audit-1.3.0.csv) records every native field, source evidence, current route, interaction guard, spatial/player-only rule, output envelope and fidelity boundary. See [Architecture](docs/ARCHITECTURE.md), [Testing](docs/TESTING.md), and [Changelog](CHANGELOG.md) for reproducible development details. Klei source scripts and raw waveform assets are intentionally not redistributed.
