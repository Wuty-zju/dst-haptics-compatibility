# Changelog / 更新日志

## 1.6.3 — 2026-11-21

- 保留无缝换角色时仍在播放的世界声音。原生和诊断模式下开始的具名声音在切回兼容时重新确认句柄。
- 暂停、设备切换和设置使旧输出失效时，同步清理去重和受击记录。被同源规则拒绝的重复声音不延长跨来源抑制。
- 发布构建以 Git 跟踪的运行时脚本为输入，采用固定 ZIP 时间和顺序。重新打包比较全部成员及校验和。
- Persistent rain survives seamless swaps and mode changes. Old deduplication no longer suppresses events after output resumes. Builds include only tracked runtime inputs from a Git checkout.

## 1.6.2 — 2026-11-18

- 切回原生模式时只清理一次兼容震动。暂停期间的校准绑定当前玩家和手柄，观察到断连、换手柄或原版震动关闭时取消。
- 具名循环在同一次采样中应用最新非零增益。正在输出的声音静音或结束时立即撤销其贡献。洞穴雨量现在参与同一套增益计算。
- 全量事件审查从实际 Lua 包络取数，逐项更新原版与实现对照。维护子任务在派工时从宿主的可用模型中选取最新 Astra 或 Sol。
- Native handoff, controller changes and paused calibration now respect output ownership. Weather loops apply the latest gain on their existing sample. Active mute and stop remain immediate.

## 1.6.1 — 2026-11-17

- 隔离失活适配器的 Shutdown/ApplyConfig，精确解绑世界监听；重装绑定已有世界，退出清除旧监听坐标。
- 按玩家和世界管理动作桥资源；实体移除时释放监听、监控、捕获和引用，保留共享状态图及新所有者。
- 安装时恢复仍存活光束的真实声音句柄观察；只扫描现有实体一次，不添加周期扫描或动画猜测。
- 重绑已打开暂停界面的设置快捷键与语言，复用包装并保护其他 Mod 及新所有者。
- 静态审计改为完整 Lua 字符串匹配：当前 404 个事件有字面引用、99 个没有；不再把较长音效名称的前缀当成当前事件。
- 审计/包络证据拒绝覆盖；空输入、零解析定义明确失败，静音 PCM 包络不再除零。
- Preserve existing event semantics, configuration keys/defaults, rumble curves and client-only boundaries. No new gameplay feedback or settings.
- Add lifecycle/GC/owner-chain and evidence regressions. Native data remains 506 definitions/503 events; hardware and remote beam visibility remain separately unverified.

## 1.6.0 — 2026-11-15

- Refactor the client pipeline into registry, device, spatial, hook, loop and action-confirmation modules; retain dynamic native definitions and client-only scope.
- Audit DST762172/build26474873 (506 definitions, 503 events), including all14 additions and their actual producer side; ignore commented-out Lua when counting references.
- Observe Shrouden beam loop/bigloop only when the native handle reports playing; preserve conditional remote visibility limits.
- Track ten native weather loops without _LP suffixes; fix same-handle replacement, approaching active distant loops and removed-entity cleanup while output is disabled.
- Cancel server-pause and deactivated-player output immediately; use static scheduling for live settings and output gates, and prevent stale tails after device changes.
- Preserve action identity, failed/cancelled replacement and final tool-hit snapshots; bound repeated work acknowledgements by native replicated state, target and time.
- Make melee/hurt approximations explicit and OFF by default. Fix real weapon lookup without invobject; remove unproven armour tags and generic flesh guesses.
- Rebind/clean up same-VM observers safely, avoid host hungry duplication, and retain native/compatibility output exclusivity.
- Unify Chinese/English prompts/logs and preserve config keys; rewrite both READMEs with installation, settings, architecture, migration and Workshop links.
- Exact waveforms, physical controller routes and remote beam-handle visibility remain unverified; GitHub publication does not update Workshop automatically.

## 1.5.0 — 2026-09-20

- 总体、工具、战斗、危险、玩家、Boss、环境、界面和循环分别支持强度/时长，0%–200%，步长 5%，默认 100%。
- 设备专用适配默认开启，支持回退通用响应；Xbox、DS4、PS5/DualSense 共用原版事件与多段包络。
- 单次包络宽度与间隔同比缩放，循环混合保留每个贡献的独立结束时间。
- 修复暂停/断连后旧尾部恢复、暂停期间新事件排队，以及远处其他玩家特殊受伤错误抑制本地受击的问题。
- 合并配置读取与倍率逻辑，缓存原版 profile，优化循环混音并扩展第三方声音钩子共存测试。
- 重写中文 README，单独提供英文说明，加入原创简约线条图标及游戏纹理。
- 动态版本打包、双语文档和图标随包分发；本机全原版倍率检查、Lua 5.1 回归及微基准已记录。
- 精确原生绝对强度/时长与 DS4/DS5 物理体感仍需真实验收，不以自动测试替代。

## 1.4.0 — 2026-09-20

- Treat verified FrontEnd/FocalPoint emitters as listener-local across every native category.
- Track the native three-dimensional audio listener instead of assuming the player transform is the listener.
- Preserve `PlaySoundWithParams` and live named-loop `SetParameter` values with exact, source-audited policies.
- Compose native category and semantic tool/combat levels, so Boss attacks obey both Boss and Combat settings.
- Defer generic local hurt briefly so an authoritative electric/freeze/burn sound can prevent duplicate feedback.
- Preserve capture-time material evidence for server-confirmed killing blows whose target is removed before replication arrives.
- Add explicit Compatibility, Native and no-motor Diagnostic modes.
- Add Steam Workshop staging validation, an original preview image, update signatures and expanded Lua 5.1 regression coverage.
- 修正 FocalPoint、本地监听者三维距离、声音/循环参数、Boss×战斗双轴倍率、特殊受击去重与击杀目标快照，并加入原生/兼容/诊断模式和创意工坊发布校验。

## 1.3.0 — 2026-09-20

- Replaced fixed animation-frame work guesses with server-confirmed `player_classified.performaction` bridging.
- Reworked melee impact to use the release `combat_replica:CanHitTarget` distance/radius rule and native material resolvers.
- Replaced broad health-change hurt detection with the replicated `attacked` pulse.
- Added RMS envelopes measured from shipped haptic WAV families for tools, impacts, swings, hunger, freeze and heat.
- Fixed local HUD/focal-point `player_only` handling, cross-route deduplication and immediate loop-channel cleanup.
- Added the complete 489-event original-vs-current audit, reproducible analysis tools and Lua 5.1 behavior tests.
- 用服务器确认动作替代固定动画帧猜测；受击、近战材质、HUD `player_only`、循环清理和波形包络均重新校准。

## 1.2.0 — 2026-09-20

- Added Xbox/XInput, DualShock 4 and PS5/DualSense response profiles.
- Added live in-world settings, controller-family override, per-category levels and spatial reach.
- Added F8 and controller pause-menu configuration entry points.

## 1.1.0 — 2026-09-20

- Added a replicated action/state bridge for client-invisible server sound paths.
- Added work, combat, hurt and hunger coverage beyond the client SoundEmitter hook.

## 1.0.0 — 2026-09-20

- Initial dynamic `haptics.lua` index, SoundEmitter compatibility layer, spatial filtering, deduplication and loop lifecycle handling.
