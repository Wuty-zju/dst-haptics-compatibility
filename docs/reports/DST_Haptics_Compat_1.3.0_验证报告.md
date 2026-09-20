# DST Haptics Compatibility 1.3.0 验证报告

日期：2026-09-20  
DST：Windows x64，build 752666  
安装目录：`C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst_haptics_compat`

## 架构结论

1.3.0 采用 Hybrid Compatibility Layer。当前游戏的 `scripts/haptics.lua` 是事件与字段的唯一事实源；SoundEmitter 捕获客户端可见的原版事件；服务器侧工作、近战和受击缺口只在复制信号能够证明动作成立后桥接；最终输出统一交给已确认可工作的 `TheInputProxy:AddVibration`。

原生 `TheHaptics` 的 Lua 注册、Profile 开关、设备更新和声音事件均存在，但当前 Windows 构建没有把原始 Haptic waveform 送到活动手柄。Lua 没有重新绑定其闭源后端或逐采样播放 WAV 的公开接口，因此不能在纯 Lua 内修复 C++ 输出端，也不能读取马达物理状态。兼容层开启时抑制原生输出以防未来双震，关闭时停止兼容震动并恢复原生开关。

## 全量原版审计

- 原版定义 492 条、唯一事件 489 条、重复 event 3 个。
- 唯一分类：PLAYER 232、BOSS 166、ENVIRONMENT 53、DANGER 13、UI 22、未指定 3。
- 唯一 `player_only=true` 事件 44 个；`audio=false` 事件 14 个；loop-like 事件 18 个。
- 原版 Lua 中找到字面调用证据的事件 390 个；其余 99 个继续动态索引，可能来自资源、动态字符串、闭源声音层或未来入口，不伪造触发。
- 本机资源含 1722 个 882 Hz Haptic WAV。树/蘑菇树砍击、普通/冰/月玻璃采矿、挖地、挥动、材质命中、饥饿、寒冷、过热已经从原始资源提取 RMS 包络；其它事件使用按原版语义分类的包络近似。

逐事件的原版 event、字段、源码证据、当前触发方式、交互保护、空间/player_only、震动方式和保真度见 `DST-Haptics-Event-Audit-1.3.0.csv`（489 行）。

## 1.3.0 关键修正

- 砍树、采矿、锤击和挖地不再按固定动画帧猜测成功；先捕获原版动作上下文，再等待 `player_classified.performaction` 的服务器结果回传。
- 近战命中不再只用固定强度。它复刻 release 版 `combat_replica:CanHitTarget` 的 3D 距离、目标半径和 0.5 预测容差，再调用原版墙/物体/生物材质 resolver；玩家装备按原版护甲优先级处理。
- 玩家受击改用 `attacked` 网络脉冲，排除饥饿、温度、制作耗血、治疗等普通 `healthdelta` 误触发。
- 挥动与真正命中保持为两个原版事件；严格原版模式允许有 whoosh 的挥空反馈，但不会凭空产生材质 impact。
- UI/HUD 的本地 FrontEnd/FocalPoint emitter 可正确通过 `player_only`；其它玩家与 NPC 的同名 player-only 事件仍过滤。
- 声音与复制桥同时看到同一原版事件时按 event、entity、source 做跨路径短窗去重。
- 具名循环在 `KillSound`/`KillAllSounds` 后立即移除 loop 通道；暂停、失效、断连、世界卸载和局内关闭适配均清理。
- Xbox/XInput、DS4、PS5 Controller/DualSense 继续使用同一原版事件语义，只在 Legacy Rumble 输出端应用各自的最短脉冲/响应校准。

## 自动验证结果

- 7 个 Mod Lua 文件全部通过 DST Lua 5.1 解析。
- 原版配置回归：492/492 定义均能生成震动 profile。
- 动作桥回归：服务器确认砍树、采矿、受击、近战材质命中通过；取消动作和超距近战不输出。
- 适配器回归：返回值/参数保留、普通声音快速旁路、Profile OFF、无手柄、暂停、严格 player_only、HUD 本地例外、空间衰减、UI 非空间、去重、循环生命周期、热插拔、Compatibility 动态开关、world unload 清理通过。
- 局内设置回归：F8/手柄入口、配置热更新、重复界面防护通过。
- 安装文件与开发源逐文件 SHA-256 一致。
- 直接启动 1.3.0 时，DST 在加载 Mod 前因 Steam 客户端未运行而退出；因此本轮没有伪称完成新的物理手柄或完整游戏内验收。此前 1.2.0 的真实前端加载已通过，1.3.0 的新增逻辑由上述 Lua 5.1 行为回归覆盖。

## 无法伪装成“100% 原版”的边界

- `AddVibration` 不能逐采样播放 Klei 882 Hz Haptic WAV，RMS 多脉冲包络是经过本机资源测量的近似。
- 引擎直接复制、且客户端没有 SoundEmitter、动作、HUD 或其它 Lua 回调的一发服务器事件，纯客户端 Mod 无法通用截获。尤其部分 Boss/环境调用只保证在客户端可见路径上覆盖；Mod 不靠猜 Boss 动画制造远端或未命中的误震。
- DS4/DS5 的直连 USB/Bluetooth 马达仍需要 DST 或 Steam Input 提供实际 Legacy Rumble 通道；纯 Lua 不能发送 HID 报告。本机没有 DS4/DS5，因此只能验证设备类型路由与输出调用，不能代替物理手感验收。

## 使用与日志

游戏原版“控制器震动”和 Mod“震动适配”必须同时开启。世界内按 `F8`，或在手柄暂停菜单按 `MENU_MISC_2` 对应键打开细粒度设置。复现问题后查看：

- Beta 分支：`Documents\Klei\DoNotStarveTogetherBetaBranch\client_log.txt`
- 正式分支：`Documents\Klei\DoNotStarveTogether\client_log.txt`

如果 Klei 修复原生 Windows Haptics，把“震动适配”设为关闭；Mod 会完整旁路兼容输出并恢复原生 `TheHaptics`。
