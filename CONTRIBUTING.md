# Contributing / 贡献

Changes must preserve the installed DST `haptics.lua` as the event source of truth. Do not add controller-button rumble, gameplay RPCs, combat changes, save data, or guessed Boss-animation triggers.

For each behavior change:

1. Identify the native event and its current source call or replicated proof.
2. Add a Lua 5.1 regression test.
3. Preserve SoundEmitter arguments, returns and lifecycle.
4. Document any approximation caused by unavailable FMOD or motor APIs.
5. Do not commit extracted Klei scripts, Haptic WAVs, logs or local filesystem paths.

Use a focused branch and open a pull request against `main`. `main` represents released or release-ready code; tags use semantic versions such as `v1.4.0`.
