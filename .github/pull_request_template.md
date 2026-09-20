## Scope

Describe the original DST haptic event or lifecycle behavior being preserved. Link native source evidence without committing Klei source or assets.

## Safety checklist

- [ ] Client-only; no gameplay RPC, save, damage or stategraph gameplay changes
- [ ] No button-to-rumble or unconfirmed animation guess
- [ ] Original SoundEmitter call arguments and return values remain intact
- [ ] Profile OFF, pause, disconnect and world unload stop output
- [ ] Lua 5.1 tests pass
- [ ] No Klei scripts, raw Haptic WAVs, logs, local paths or credentials are included

## Validation

List automated tests and any physical Xbox/DS4/DualSense route tested.
