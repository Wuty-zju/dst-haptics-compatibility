# Controller Acceptance Matrix / 手柄验收矩阵

Code support means DST recognizes the device type and exposes it through `TheInputProxy`. Physical acceptance additionally requires a real motor test on that route; Lua cannot infer it.

The 1.6.3 review on November 21 replayed output generation changes and live named sounds in Lua 5.1. The most recent local client log still shows the Workshop build 1.5.0. Physical results for 1.6.3 require device testing. [Review and evidence](reports/1.6.3-review.md)

The 1.6.2 review on November 18 replayed pause, Profile OFF and controller ID/type transitions. Two newly captured logs record 14 initializations of the subscribed 1.5.0 item. Physical motor and USB/Bluetooth acceptance for 1.6.2 is still open. [Review and evidence](reports/1.6.2-review.md)

1.6.1 (2026-11-17): lifecycle ownership, GC and current-native regressions pass.
No new physical or in-game acceptance was performed. The newest available client
log remains the November 7 session loading 1.5.0; pending routes stay pending.

1.6.0 (2026-11-15): current-native data and simulated integration checks were rerun,
including strict defaults, server pause and beam observers. No new game launch or
physical motor acceptance was performed for 1.6.0. All physical pending routes below
remain pending. The retained November 7 load record is for 1.5.0, not 1.6.0.

2026-09-20 / 1.5.0 historical release record: DualSense enumeration and successful game loading were recorded in the progress notes, but the original enumeration output/log from that day was not archived. The user authorized reduced physical testing. USB/Bluetooth subjective feel tests remain unperformed; enumeration and successful loading do not prove physical motor response. No DualShock 4 was found in that historical query.

2026-11-15 evidence refresh: a retained November 7 client log directly shows Workshop item 3805091756 loading version 1.5.0 and 506 definitions / 503 unique events. It was copied and hashed locally. This is a loading observation from that earlier session, not a new physical test. See [evidence provenance](maintenance/EVIDENCE.md).

| Controller | Connection | DST route | Status | Evidence needed |
|---|---|---|---|---|
| Xbox/XInput | Windows XInput | Type 1 | User-reported historical `XInputSetState` / `TheInputProxy:AddVibration` success; not a full 1.5.0 acceptance | Repeat weak/medium/strong calibration and representative game events for the current release/game build |
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
