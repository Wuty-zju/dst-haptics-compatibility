# Architecture / 架构

## First principle / 第一性原理

The mod does not invent gameplay-to-rumble rules. The installed game's `scripts/haptics.lua` is loaded at startup and converted into an O(1) `event -> effect` index. An output is eligible only when the current native table defines that exact event with `vibration=true`.

本 Mod 不自行发明“玩法动作 → 震动”清单。启动时读取当前游戏的 `scripts/haptics.lua`，建立 O(1) 的 `event -> effect` 索引；只有当前原版表确实定义、且 `vibration=true` 的 event 才允许输出。

```text
native haptics.lua
        ↓ dynamic index
real client SoundEmitter event ─────────────┐
                                            ├─ ownership / spatial / dedupe / lifecycle
server-confirmed local action-state gap ────┘
        ↓
native intensity + measured/semantic envelope
        ↓
controller-family Legacy Rumble calibration
        ↓
TheInputProxy:AddVibration
```

## Why hybrid / 为什么是混合层

Wrapping `SoundEmitter.PlaySound` and `PlaySoundWithParams` is the closest Lua-level equivalent to the native sound-event route. It preserves original timing and automatically sees future events. However, a dedicated server can play a sound and replicate it through the engine without calling the client Lua wrapper. That is why the old pure sound wrapper missed ordinary chop/mining hits and some combat material impacts.

The bridge is deliberately narrow:

- It captures the local buffered action from the original `wilson_client` state.
- It waits for replicated `performaction`; cancelled or rejected work never outputs.
- Melee impact additionally passes the release client-safe target/range rule before native material resolution.
- Local hurt uses the replicated `attacked` pulse, not generic health changes.
- Hungry uses an entering edge of the original audio-free animation.

客户端完全无 Lua 信号的服务器一次性声音仍无法通用捕获。项目拒绝用 Boss 动画名或按键去猜，因为这种“补全”会导致远端 Boss、挥空、取消动作和预测失败时错误震动。

## Preserved fields / 保留字段

`event`, `vibration`, `vibration_intensity`, `audio`, `audio_intensity`, `player_only`, and `category` are kept from the current native table. Duplicate events follow registration order and use the final definition; all three current duplicates have equivalent physical vibration values, so this does not alter the present motor result.

## Output model / 输出模型

- Intensity uses a monotonic non-saturating mapping `1-exp(-0.35*x)` before user/category/spatial calibration.
- UI/HUD bypasses world distance. PLAYER, DANGER, ENVIRONMENT and BOSS use category-specific near/far policies with smoothstep falloff.
- `player_only` requires local `ThePlayer`; local FrontEnd/FocalPoint emitters are accepted only as a provable local HUD context.
- Named loops track `PlaySound(event,name)`, `PlayingSound`, `SetVolume`, `KillSound`, `KillAllSounds`, entity validity, pause, controller availability and world unload.
- Compatibility mode suppresses native `TheHaptics` output. Turning it off stops compatibility output and restores the native setting, preventing future double rumble.

## Controller families / 手柄族

Xbox/XInput (DST type 1), DS4 (type 2), PS5 Controller (type 7) and DualSense (type 11) share exactly the same event logic. Profiles only compensate minimum pulse duration, gain and response shape at the Legacy Rumble output layer. Steam Input may present a PlayStation controller as XInput; the live menu therefore allows a manual family override.

Lua cannot send DS4/DS5 USB or Bluetooth HID reports. Physical output on those devices still requires DST or Steam Input to expose a rumble channel to `TheInputProxy`.

## Fidelity boundary / 保真边界

The game ships 1722 mono 16-bit, 882 Hz haptic WAVs, but Lua exposes neither sample playback nor motor-state feedback. The mod uses measured RMS envelopes for core families and semantic multi-pulse envelopes elsewhere. It preserves event semantics, relative intensity, broad duration/rhythm and lifecycle; it does not claim sample-identical Klei waveforms.

