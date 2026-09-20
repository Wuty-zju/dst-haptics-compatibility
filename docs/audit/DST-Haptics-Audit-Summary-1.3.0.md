# DST Haptics Compatibility 1.3.0 — 全量审计摘要

审计基准：本机当前 `scripts/haptics.lua` 与解包后的原版 Lua 源码；定义 492 条，唯一 event 489 条。逐事件明细见同目录 CSV。

## 全量统计

| 项目 | 数量 | 结论 |
|---|---:|---|
| 唯一原版 event | 489 | 全部动态进入 O(1) 索引，无手抄事件白名单 |
| 有 Lua 字面触发证据 | 390 | 明细记录文件、行号和原始调用 |
| 无字面引用 | 99 | 保留动态/资源/未来入口，不伪造触发 |
| `audio=false` | 14 | 仍保留震动；Hungry 另设状态桥，其余 UI/地面移动仍由 PlaySound 调用进入 |
| `player_only=true` | 44 | 严格要求 emitter 对应本地 ThePlayer |
| `_LP`/loop | 18 | 具名生命周期管理，停止、静音、暂停和卸载清理 |
| 直接取样本机 Haptic WAV 包络的语义事件 | 104 | 工具、命中、挥动、饥饿、寒冷、过热 |

## 分类与当前机制

| 原版分类 | 唯一事件数 | 原版逻辑 | 当前实现 | 防止“傻震” |
|---|---:|---|---|---|
| DANGER | 13 | Wilson 受击、饥饿、Charlie、冻伤/过热等；原版表决定强度和 player_only | 原声钩子；Hungry 动画进入沿；受击用服务器 attacked 脉冲 | 排除普通 healthdelta（饥饿、建造耗血、治疗）；本地玩家限制；暂停/总开关 |
| PLAYER | 232 | 移动、交互、装备、复活、采集、工具、挥动和 84 类材质 impact | 原声钩子；工作用 performaction 回传；近战 impact 用 client-safe 命中等价校验 | 不监听 A/X；动作取消/失败不震；挥空无材质 impact；挥动仍尊重原版事件 |
| ENVIRONMENT | 53 | 地震、裂隙、船/地形、环境实体和新内容 | 客户端可见原声事件动态匹配 | 8–46 单位平滑衰减，远处归零 |
| BOSS | 166 | 脚步、重击、落地、咆哮、技能、阶段/死亡 | 客户端可见原声事件动态匹配，循环按具名 sound 生命周期 | 12–64 单位平滑衰减；同实体短窗去重；纯服务端无 Lua 回调的事件不伪造 |
| UI | 22 | 菜单、HUD、礼物、制作、图鉴等 | FrontEnd/FocalPoint SoundEmitter 精确钩子 | 不做世界距离衰减；仍服从原版总开关和去重 |
| UNSPECIFIED | 3 | 原版未填 category 的 HUD 条目 | event 路径识别为 UI | 非空间；不错误套用世界距离 |

## 关键原版逻辑与实现对照

| 机制 | 原版原始逻辑 | 1.3.0 实现 |
|---|---|---|
| 砍树 | 目标 `workable` 成功回调在树的 SoundEmitter 播放 axe/mushroom/beaver/rock-tree 事件 | 捕获本地动作上下文，仅在 `player_classified.performaction` 回传后按目标标签发出同一个 haptics event |
| 采矿 | `PlayMiningFX` 在动作帧按 frozen/moonglass/crystal 选择三个原版事件 | 服务器动作回传后按同一标签顺序选择；取消动作不震 |
| 锤击/挖地 | SGwilson 动作帧播放 `wilson/hit` 或 `wilson/dig` | 成功动作回传触发；锤皮肤音若在 haptics.lua 中存在则优先 |
| 武器挥动 | SGwilson_client 在攻击开始播放 whoosh/weapon/角色专属声音，挥空也可能存在 | 直接钩原始客户端声；不把挥动伪装成命中 |
| 近战命中 | `Combat:DoAttack` 先 `CanHitTarget`；成功路径由目标 `GetImpactSound` 按护甲、墙、物体、生物材质/尺寸/利钝播放 | ATTACK 回传后复刻 release 版 client-safe 3D 距离与 0.5 预测容差，再调用原版 resolver；本地可见装备按原版护甲优先级解析 |
| 玩家受击 | `Combat:GetAttacked_Internal` 推送 `attacked`，SGwilson 根据状态播放 hit/电击/特例 | 使用 player_classified 的服务器 attacked 脉冲而不是“任何掉血”；特殊声音仍由原声钩子覆盖 |
| Boss/环境 | Boss/环境实体 SG 或 prefab 在具体动画帧播放已登记声音 | 对客户端 Lua 可见调用按 event 精确触发并空间衰减；引擎直接复制且不回到 Lua 的一发声音是纯客户端 API 的明确边界 |
| 循环 | `PlaySound(event,name)` 开始，`KillSound(name)`/状态退出停止，SetVolume 可变 | 同名注册、`PlayingSound` 复核、音量跟随、失效/暂停/卸载即时清理 |
| 强度 | 原版 `vibration_intensity`（0.5/1/1.5/2/2.5/3/10）+ 原始 WAV | 单调非饱和映射 `1-exp(-0.35*x)`，再乘 WAV 包络、分类/总倍率、距离与手柄校准 |
| Xbox/DS4/DS5 | 原版通过当前输入设备输出 | 同一事件语义；按 DST 设备类型 1/2/7/11 选择 Legacy Rumble 脉冲时长/增益校准 |

## 第一性原理结论

事件的唯一事实源仍是当前游戏 `haptics.lua`；Mod 不从按键或玩法状态另造一套事件。只有原版事件已经发生、或服务器复制信号足以证明原版动作路径成立时才桥接。空间、归属、去重、循环生命周期和原版总开关均在输出前处理。

无法由纯 Lua 完全恢复的是两项：原始 WAV 的逐采样左右马达波形，以及完全绕过客户端 Lua 的服务器复制一发声音。前者已用本机 WAV 的 RMS 包络近似；后者不会用“看见 Boss 动画就猜一次”来制造误震，明细表逐项标为条件覆盖。
