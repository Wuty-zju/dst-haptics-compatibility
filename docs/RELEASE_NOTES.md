# DST Haptics Compatibility 1.4.0

This release tightens the compatibility layer around the current native `haptics.lua` instead of adding new gameplay rumble rules.

## Highlights

- Correct listener-local FrontEnd/FocalPoint handling for equip, burn, worm travel/digestion and lunar supernova feedback.
- Three-dimensional attenuation from DST's actual `Sim.SetListener` position.
- Audited `PlaySoundWithParams` and named-loop `SetParameter` support.
- Native category levels compose with tool/combat semantic levels, including Boss attacks.
- Special hurt sounds can suppress the delayed generic hit fallback.
- Server-confirmed killing blows retain capture-time material evidence if the target disappears before replication arrives.
- Explicit Compatibility, Native and no-motor Diagnostic modes.
- Expanded Lua 5.1 tests, current-build haptics signature, clean Workshop staging and original preview artwork.

## Boundaries

Lua still cannot play Klei's waveform samples directly, read physical motor state or observe every server-direct FMOD trigger. The mod keeps documented envelope/spatial approximations and does not invent animation or button triggers to hide those engine limits.

## Installation

Extract the archive so the file is at `Don't Starve Together/mods/dst_haptics_compat/modinfo.lua`. Enable the client mod and keep DST Controller Vibration on for Compatibility mode.
