# Contributing / 贡献

Changes must preserve the installed DST `haptics.lua` as the event source of truth. Do not add controller-button rumble, gameplay RPCs, combat changes, save data, or guessed Boss-animation triggers.

For each behavior change:

1. Identify the native event and its current source call or replicated proof.
2. Add a Lua 5.1 regression test.
3. Preserve SoundEmitter arguments, returns and lifecycle.
4. Document any approximation caused by unavailable FMOD or motor APIs.
5. Do not commit extracted Klei scripts, Haptic WAVs, logs or local filesystem paths.

Use a focused branch and open a pull request against `main`. `main` represents released or release-ready code; tags use semantic versions such as `v1.4.0`.

Start with [AGENTS.md](AGENTS.md), [current status](docs/STATUS.md) and
[the document index](docs/INDEX.md). Use `codex/<task>` branches for agent work.
Parallel writers need separate worktrees and explicit file ownership; read
[the coordination guide](docs/maintenance/MULTI_AGENT.md) before delegating.

Run `python tools/verify.py` with Lua 5.1 or the Windows DLL route. Supply current
native scripts explicitly for the separate original-data check; a SKIP does not
prove native coverage. Keep reports in a new `.local/evidence/<session>/` path.
See [testing](docs/TESTING.md) for the complete command. Build into a fresh directory
and retain published ZIPs/checksums; the builder refuses existing output files.
