# DST Haptics Compatibility 1.4.0 验证报告

日期：2026-09-20  
DST：Windows x64，build 752666  
核心实现提交：`42c7052389c1f46800fdf2d37ab1ca7938abb630`  
安装目录：`C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\dst_haptics_compat`

## 发布结论

1.4.0 继续采用 Hybrid Compatibility Layer。当前安装版本的 `scripts/haptics.lua` 是 event 与原版字段的唯一事实源；客户端可见声音走 SoundEmitter 入口，服务器侧工作、近战和受击缺口只在复制信号能够证明事件成立后桥接，输出统一进入 `TheInputProxy:AddVibration`。Mod 不从 A/X 按键、攻击动画或 Boss 动画猜测事件。

本版本重点修正监听器、本地 UI/玩家事件、原版声音参数和受击/击杀边界，而不是增加一份手写玩法事件表。兼容输出、原生输出和仅诊断模式互斥，因此不会有意同时驱动原生与兼容马达。

## 原版来源与事件覆盖

- 当前原版 `haptics.lua` SHA-256：`9fc8b8637971daceb71cadca1ef15a3b6d46218c7f39729c767eb51dffa7063c`。
- 492 条定义、489 个唯一 event；全部定义均能建立输出 profile。
- 390 个唯一 event 在解包 Lua 中找到字面触发证据；其余 99 个继续动态索引，但不伪造触发。
- 当前资源审计到 1722 个 Haptic WAV。Lua 无逐采样播放接口，所以包络输出仍是测量后的近似。
- `event`、`vibration`、`vibration_intensity`、`audio`、`audio_intensity`、`player_only`、`category` 均保留并进入索引/诊断；`audio_intensity` 因缺少已证明的马达含义只记录，不擅自缩放。

## 1.4.0 新增校验与修正

- 链式包装 `Sim.SetListener`，空间事件使用真实 3D 音频监听器位置，无法取得时才回退到 `ThePlayer`。
- 原版通过 `TheFrontEnd`/`TheFocalPoint` 播放的装备、燃烧、虫洞移动/消化、月亮超新星等事件按监听器本地语义处理；普通 nil emitter 不因此放行。
- `PlaySoundWithParams` 参数完整透传；仅对当前源码中已审计的 event/parameter 建立单调策略，未知参数保持 1.0 中性倍率。
- 具名循环接收 `SoundEmitter.SetParameter`、`SetVolume`、`KillSound`、`KillAllSounds` 生命周期；lighter、whirlpool、crabking magic 和 lunar supernova 使用已审计参数，播放位置类参数不误改强度。
- 原版 category 倍率与工具/战斗语义倍率分轴相乘；Boss 战斗事件同时响应 Boss 与 Combat 设置。
- 本地特殊受击音（电击、冻结、过热、燃烧、Charlie）会抑制相邻帧的通用 Wilson hit fallback，单独的 `attacked` 复制脉冲仍可产生通用受击反馈。
- 服务器确认的致死一击若在回传前删除目标，可在保守时间窗内使用动作捕获时的 GUID、位置和原版材质证据；取消、超距或未确认动作不输出。
- 增加弱/中/强显式校准脉冲与运行指标。校准脉冲只由用户在设置中主动选择，不属于玩法触发。

## 自动验证结果

- 13 个 Lua 文件（运行时代码与测试）全部通过 DST 兼容 Lua 5.1 解析。
- 原版 profile 回归：`definitions=492`、`vibrating=492`。
- 客户端动作桥回归通过，包括服务器确认工具动作、近战材质、特殊受击仲裁、已删除目标的确认击杀与拒绝/超距过滤。
- 适配器回归通过，包括参数/返回值透传、普通声音快速旁路、Profile OFF、无手柄、暂停、`player_only`、六类 FocalPoint 本地事件、3D 监听器、空间衰减、组合倍率、去重、循环参数/停止、热插拔、模式切换与 world unload 清理。
- 参数策略与局内设置回归通过；Xbox、DS4、PS5/DualSense 设备别名和响应曲线路由通过自动测试。
- GitHub `release/1.4.0` CI run `35499586800` 通过。
- 最终 Workshop staging 与本机安装目录比较 10 个文件，SHA-256 差异为 0。
- ZIP SHA-256：`1e2bbe5a8ae44929932cc3628a04c90ef3b8d95f1149639f5eccf209286e83e2`。

## 真实运行与硬件边界

- 已知本机 Xbox/XInput 原生 `XInputSetState` 与 DST `TheInputProxy:AddVibration` 路径能够驱动马达。
- 1.4.0 的自动测试不能替代物理手感测试。DS4/DS5 的设备类型、别名、过滤和曲线均已覆盖，但 USB/Bluetooth 实际马达仍需真实手柄以及 DST 或 Steam Input 提供 Legacy Rumble 输出路径。
- 本轮尝试从后台开发会话冷启动 DST 时，游戏日志在 Steam 初始化阶段报告 `Steam failed to initialize, result=1`；通过 Steam `-applaunch` 也没有生成新游戏进程/日志。因此不能把 1.3.0 的成功前端启动冒充为 1.4.0 冷启动验收。安装文件已精确同步，仍建议账号持有人从可见 Steam 客户端启动一次并执行硬件矩阵。
- Lua 无法读取“物理马达是否移动”、FMOD 最终 audible state 或 Klei Haptic WAV 的逐采样马达通道。本项目明确把这些列为近似或待物理验收，不声称 100% 原始波形。

## Steam Workshop 与后续原生修复

构建脚本产生干净内容目录、ZIP、SHA-256 和独立预览图；内容目录不含 Git、测试、审计工具、Klei 源码、原始 WAV、日志或本机绝对路径。Mod 元数据声明纯客户端，服务器和其他玩家无需安装。

实际创建/更新 Workshop item 需要仓库/条目所有者的已登录 Steam 会话、PublishedFileId 与 Steam Workshop 法律协议确认，不能由后台测试替代。发布时使用 `docs/WORKSHOP_DESCRIPTION.md` 和 `docs/RELEASE_NOTES.md`。

如果 Klei 修复 Windows 原生 Haptics，将“震动适配”关闭或把输出模式切到“原生”。兼容层会停止自身通道并恢复原生 `TheHaptics` 开关，不应保留双重输出。
