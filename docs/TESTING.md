# Testing / 测试

## Automated checks / 自动检查

The test suite intentionally runs against a Lua 5.1 DLL because DST does not support modern Lua syntax. It covers:

- parsing every distributable Lua file;
- all 492 native definitions receiving a profile;
- server-confirmed chop/mine/hurt/melee bridge behavior;
- no material impact for an out-of-range attack;
- argument and return-value preservation in SoundEmitter wrappers;
- fast bypass for unrelated sounds;
- Profile OFF, no controller, pause and compatibility OFF;
- `player_only`, local HUD exception, UI/non-spatial and category spatial falloff;
- deduplication, loop volume/kill/unload cleanup and hot-plug output refresh;
- live settings entry/refresh behavior and explicit weak/medium/strong calibration pulses.

Run on Windows with an extracted current `scripts` directory and a DST-compatible `lua51Original.dll`:

```powershell
$python = "path\to\python.exe"
$scripts = "path\to\extracted\scripts"
& $python tools\validate_lua.py --mod-root . --lua-deps "path\to\lua51\deps"
& $python tools\run_lua51.py tests\test_original_haptics.lua --mod-root . --original-scripts $scripts
& $python tools\run_lua51.py tests\test_client_action_bridge.lua --mod-root .
& $python tools\run_lua51.py tests\test_adapter.lua --mod-root .
& $python tools\run_lua51.py tests\test_haptic_parameters.lua --mod-root .
& $python tools\run_lua51.py tests\test_runtime_settings.lua --mod-root .
```

## Rebuilding the audit / 重建审计

Klei Lua sources and raw haptic WAVs are not redistributed in this repository. Point the tools at your legally installed/extracted current game data:

```powershell
& $python tools\audit_haptics.py --scripts $scripts --wav-root "...\data\haptics\vibration\vibration" --out build\audit
& $python tools\analyze_waveform_envelopes.py --wav-root "...\data\haptics\vibration\vibration" --out build\audit\core_envelopes.json
& $python tools\build_haptics_report.py --audit build\audit\audit.json --out build\reports --version 1.4.0
```

## Physical acceptance / 物理验收

Automated tests cannot feel a motor. Manual acceptance should cover continuous chop/mine cadence, swing versus hit, local hurt, near/far Boss behavior, UI, cave transitions, disconnect/reconnect and leaving a world while a loop is active. DS4/DS5 should be tested over both direct/Steam Input routes that actually expose rumble to DST. Record results in [the hardware matrix](HARDWARE_MATRIX.md).
