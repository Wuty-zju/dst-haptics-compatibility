# Changelog / 更新日志

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

