# Changelog / 更新日志

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
