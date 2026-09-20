# DST Haptics Compatibility

[中文说明](README.md)

A client-only compatibility mod for Don't Starve Together on Windows. It connects observable native haptic events to the game's working `TheInputProxy` rumble output, with live controls for intensity, duration and controller response.

## Install

Download a published package from [Releases](https://github.com/Wuty-zju/dst-haptics-compatibility/releases). Extract it so `mods/dst_haptics_compat/modinfo.lua` sits inside your DST installation. Enable the client mod, then enable the game's Controller Vibration setting. Servers and other players do not need the mod.

The `release/1.5.0` branch is under development. Its changes are not a declaration of physical controller acceptance.

## Adjust feedback in game

Press F8 in a world, or use the haptics shortcut shown on the controller pause menu. Saved changes apply within about half a second.

Intensity and duration each have 41 positions, from 0% to 200% in 5% steps. Both default to 100%. Adjust the global controls or tool, combat, danger, player interaction, Boss, environment, UI and loop controls. Zero mutes the corresponding output.

The native category and semantic type are independent multipliers. A Boss combat event uses Global × Boss × Combat. A named Boss loop uses Global × Boss × Loop. At 100% on every axis, the measured or approximated native-compatible envelope is unchanged. This baseline cannot be claimed to equal Klei's inaccessible motor waveform sample for sample.

One-shot duration scales both pulse widths and their spacing. Loop duration changes individual pulse widths while the original sound owns the start/stop lifecycle. Increasing loop duration does not keep a killed sound vibrating. The hardware motor limit can cap high intensity combinations.

## Controllers

Xbox/XInput, DualShock 4, PS5 Controller and DualSense use the same event logic. Controller Adaptation is on by default and applies family-specific response curves to the native-compatible multi-pulse envelope. Turn it off for generic output. Force a family when Steam Input presents a PlayStation controller as virtual XInput.

DS4 and DS5 require a rumble path exposed by DST or Steam Input. This Lua mod does not send USB/Bluetooth HID reports and cannot provide DualSense adaptive triggers or sample-accurate high-frequency haptics. The [hardware matrix](docs/HARDWARE_MATRIX.md) records actual testing separately from code coverage. Weak/medium/strong calibration pulses are explicit user tests, not gameplay triggers.

## How it works

At startup, the mod reads the installed game's `haptics.lua`. SoundEmitter hooks observe actual client sound events and audited parameters. For server-side tool hits, melee impacts and local hurt, a narrow bridge waits for replicated confirmation and uses native material rules. Button presses and unconfirmed animations do not cause rumble.

The compatibility layer retains native event metadata, player ownership, relative intensity, category and named-loop lifecycle. World events use listener-relative falloff; local UI events do not. Compatibility mode suppresses native Haptics output to prevent double feedback. Native mode restores the game's path. Diagnostic mode records events without either motor output.

Core waveform families use measured RMS envelopes; other families use semantic approximations. Engine-replicated sounds with no client Lua observation cannot all be intercepted. Future events enter the dynamic index, but their output still requires an observable trigger.

## Troubleshooting

Check the game's Controller Vibration switch, mod compatibility switch, output mode and zero-valued tuning settings first. Enable debug logging and reproduce once. Logs live in `Documents/Klei/DoNotStarveTogether/client_log.txt`; the beta branch commonly uses `DoNotStarveTogetherBetaBranch`.

If Klei repairs native output, turn Compatibility off or choose Native mode. Do not enable two copies of this mod from local installation and Workshop at once.

## Development

See [the 1.5.0 plan](docs/PLAN-1.5.0.md), [progress notes](docs/notes/1.5.0-progress.md), [architecture](docs/ARCHITECTURE.md), [tests](docs/TESTING.md) and [Workshop packaging](docs/STEAM_WORKSHOP.md). The repository excludes Klei source scripts and raw waveform assets. Original icon artwork lives in `assets/icon.svg`.
