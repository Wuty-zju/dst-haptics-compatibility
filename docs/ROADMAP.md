# Roadmap / 后续计划

## Delivered in 1.4.0

- Listener-local FrontEnd/FocalPoint handling and 3D `Sim.SetListener` attenuation.
- Audited one-shot/loop parameter policies and combined category/semantic scaling.
- Generic hurt arbitration, killing-blow capture snapshots, explicit output modes and Workshop staging checks.

## Open validation

- Re-run the 489-event audit after every significant DST update and investigate new no-reference events.
- Add measured waveform families only where shipped assets provide stable evidence; avoid event-specific guesses.
- Expand hardware acceptance across Xbox, DS4 and DualSense, USB/Bluetooth and Steam Input modes.
- Watch for a future Klei native Windows fix. Compatibility OFF is the supported migration path; native and compatibility outputs must never intentionally run together.
- If Klei exposes a public waveform or attenuation API, replace envelope/spatial approximations with the native values.
