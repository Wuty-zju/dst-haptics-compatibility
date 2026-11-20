# Architecture / 架构 — 1.6.x

## Contract / 语义契约

当前安装的 `haptics.lua` 是事件数据源。启动时构建 O(1) 索引，保留原版完整记录和
同名末条定义。原版 mainfunctions.lua 按顺序提交全部记录。C++ 的同名冲突行为在 Lua 中不可见。兼容层每名输出一次。当前三组中两组字段相同，iceboulder_smash 的分类随末条取 BOSS。只有 `vibration=true` 的当前事件允许输出。506/503是本次快照计数，
不是运行时代码里的覆盖目标。

严格默认接受客户端真实声音、已审计的工具动作确认与本地/复制状态证明。
近战和受击复制信号不等于对应原版声音；两个近似补偿开关默认关闭，并以不同source标识。

## Modules / 模块职责

| 模块 | 职责 |
|---|---|
| modmain.lua | 专用服务器旁路、模块缓存和客户端安装编排 |
| haptic_adapter.lua | 组合根、事件资格/去重、单次调度、诊断、配置与生命周期API |
| haptic_registry.lua | 原版表索引与profile预计算 |
| haptic_hooks.lua | 声音和listener钩子的安全链式安装/撤销，保护参数、nil及返回元组 |
| haptic_device.lua | Profile/模式/暂停/设备门控，原生输出互斥与设备响应 |
| haptic_spatial.lua | player_only、已核实本地emitter及监听器距离 |
| haptic_loops.lua | 具名声音记录、参数/音量、替换/停止、实体有效性和循环混合 |
| haptic_profiles.lua | 测得的核心包络、语义回退和少量原版持续声音元数据 |
| haptic_parameters.lua | 仅针对已审计参数的归一化策略 |
| haptic_tuning.lua / haptic_mixer.lua | 纯倍率计算 / 按各贡献结束时间混合 |
| client_action_bridge.lua | 动作身份、失败/替换清理、有限工具连续确认和显式近似 |
| haptic_observers.lua | 只读查询新增光束的真实loop/bigloop句柄 |
| haptic_config.lua / localization.lua / runtime_settings.lua | 统一配置、中英日志/提示和局内热设置 |

没有外部服务、常驻进程、RPC、存档变更或伤害/动作结果改写。模块使用Mod本地加载器，
不把项目私有模块塞入全局package.loaded。

## Observability / 真实触发路径

声音包装先调用原函数，再保护性地处理兼容层；自身异常不会破坏原声音的返回值。
未匹配声音快速退出。KillSound、KillAllSounds、SetVolume、SetParameter同样保留原行为；
同名非Haptic声音替换已有loop时撤销旧反馈。

服务器可能绕过客户端Lua复制声音。新增14事件逐项见
[触发路径审计](audit/1.6.0-trigger-paths.md)。不从Boss动画、死亡时间或prefab名称
推断一次性声音。光束只在原表定义存在、PlayingSound严格返回true时登记，共用声钩记录；
100ms观察和85ms生命周期采样并非原版逐帧时序复现。

工具桥保存预览动作的身份、工具及末击event快照；performaction确认才输出。
原版成功确认会先ClearBufferedAction（进而Fail）再同tick发performaction，因此失败清理
延后执行。新预览/失败/代次变化清理旧上下文。连续工具确认只在有限上下文与匹配的
权威工作状态下复用；网络布尔确认没有action ID，仍存在已披露的极端时序边界。

hungry的原版producer在funnyidle分支，并非没有PlaySound。host使用声钩；remote的
权威funnyidle状态与实际hungry分支动画组合上升沿提供窄桥，关闭/暂停不积压旧边沿。

## Output / 输出与空间

原版vibration_intensity经单调映射 `1-exp(-0.35*x)` 后乘包络、音量、已审计参数、
总体/分类/语义倍率、空间和设备响应。常见0.5..3保留余量，最终输出限定0..1。
100%表示未加用户倍率的兼容基准，不是物理马达校准证明。

PLAYER、DANGER、ENVIRONMENT、BOSS分别采用平滑近/远衰减。UI和经过核实的
FrontEnd/FocalPoint本地声音不走世界距离；player_only资格先于UI非空间策略。
已审计的世界天气emitter不是地图原点声源。缺失category仍按现有玩家回退策略处理，
不修改原版原记录。距离、FMOD音量与实际可听性仍是近似。

核心波形沿用9月原版资源的RMS包络；其余按语义生成多段短脉冲。当前资源有1762个WAV，
但并未把每个event与FMOD bank逐一精确映射，也没有原始采样/左右马达播放API。

## Lifecycle / 生命周期

- 兼容输出和原生TheHaptics互斥；Native保持原生路径，Diagnostic关闭马达。
- serverpauseddirty立即停止并提升代次；staticScheduler在普通调度器暂停时继续检查总开关、设备和热设置。
- 单次回调检查代次和实体有效性。兼容输出失效时，同步释放该代次的去重与特殊受击记录。只有通过同源去重的事件才开始新的跨来源窗口。
- 兼容、原生和诊断模式均记录真实的具名声音。进入兼容输出后按现有采样核对 `PlayingSound`、归属、距离和参数。原生和诊断模式的观察只记录句柄，不探测或驱动兼容输出。
- 无缝换角在原版旧角色失活通知中清理旧角色的声音和本地专属记录，保留世界持续声。普通失活和退世界清空所有循环。
- loop按emitter+name管理；循环外的实体清理不因手柄断开而停止。远处已观察loop在接近后可恢复。
- 雨/冰雹等10个无_LP原版持续声有显式生命周期元数据，不把所有具名短声音都变成无限循环。
- 循环贡献分别结束，混合为O(n log n)最大值包络；短强效果不继承长弱效果的时长。
- 显式校准在暂停期间最多等待 10 秒。恢复时核对同一玩家、设备编号和设备类型。观察到原版开关关闭、断连、设备或玩家变化都会取消。
- 退出兼容模式时，先停止兼容输出，再恢复原生设置。此后 Native 模式的轮询、设置、停用和退出均由原生路径管理输出。
- 普通循环参数或音量更新合并到下一次既有采样。活跃贡献静音或 Kill 时立即重算存量混合。地面和洞穴雨声分别使用原版组件提供的 intensity 参数。
- Shutdown撤销自身钩子与任务，保留其他Mod后来包装的函数；重复Install更新配置，不重复加worker。
- 1.6.1把玩家/世界监听与任务归属到实体，onremove即释放引用；旧API关闭/设置调用失效。安装时重绑当前世界、存活光束和暂停屏幕，现有实体/屏幕只访问一次，不进入轮询或声音热路径。

## Controllers and language / 手柄与语言

Xbox/type1、DS4/type2、PS5/type7与DualSense/type11只在Legacy Rumble输出端应用不同
响应曲线、增益和最短脉冲；事件逻辑一致。可手动指定被Steam Input映射后的设备族，
或关闭设备适配。曲线是经验参数，不宣称完整物理校准。

DS4/DS5需要DST/Steam Input暴露输出通道；无HID bridge、自适应扳机或DualSense高频触觉。
配置页运行在独立沙箱，用固定双语标签；运行时语言默认中文，提示/日志热切。
机器字段和reason标识保持稳定，原生错误文本不翻译。

## Verification / 验证边界

Lua5.1、模块集成、配置迁移、原版全定义和触发路径回归由统一工具检查。原版脚本、
原始日志和机器路径仅本地保存。实机加载、马达体感、USB/蓝牙、洞穴和远程光束句柄
仍与模拟测试分开记录：[测试](TESTING.md) · [硬件矩阵](HARDWARE_MATRIX.md)。
