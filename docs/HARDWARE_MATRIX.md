# Controller Acceptance Matrix / 手柄验收矩阵

Code support means DST recognizes the device type and exposes it through `TheInputProxy`. Physical acceptance additionally requires a real motor test on that route; Lua cannot infer it.

2026-09-20 / 1.5.0 release check: after the user connected DS5 and exited DST, Windows enumerated DualSense Wireless Controller with OK status. DST was restarted and its fresh log confirmed version 1.5.0 and 489 indexed events (492 definitions), without a mod load error. The user authorized reduced physical testing. USB/Bluetooth subjective feel tests remain unperformed; enumeration and successful loading do not prove physical motor response. No DualShock 4 was found in the present-device query.

| Controller | Connection | DST route | Status | Evidence needed |
|---|---|---|---|---|
| Xbox/XInput | Windows XInput | Type 1 | Confirmed by existing local `XInputSetState` and `TheInputProxy:AddVibration` tests | Repeat weak/medium/strong calibration and representative game events for 1.4.0 |
| Xbox | Steam Input | Virtual XInput/generic | Code-covered, not separately felt in this release run | Record detected type/name and three test pulses |
| DualShock 4 | USB | Type 2 or Steam Input | Automated type/calibration tests pass; physical route pending | Record direct/Steam Input mode, type/name, weak/medium/strong result |
| DualShock 4 | Bluetooth | Type 2 or Steam Input | Automated type/calibration tests pass; physical route pending | Same as above plus disconnect/reconnect |
| PS5/DualSense | USB | Type 7/11 or Steam Input | Automated aliases/calibration tests pass; physical route pending | Record type/name and Legacy Rumble response |
| PS5/DualSense | Bluetooth | Type 7/11 or Steam Input | Automated aliases/calibration tests pass; physical route pending | Same as above plus disconnect/reconnect |

## Manual sequence

1. Enable DST Controller Vibration and Compatibility output mode.
2. Open the in-world Mod configuration with F8 or the pause-menu shortcut.
3. Change Calibration Pulse from OFF to Weak, back to OFF, then Medium, OFF, then Strong.
4. Enable Debug Logging and record controller ID, type, family and name from `client_log.txt`.
5. Verify tool hit, swing, material impact, local hurt, near/far Boss, UI, one named loop and world exit.
6. Repeat after disconnect/reconnect and, where available, with Steam Input enabled and disabled.
