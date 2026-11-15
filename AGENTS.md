# DST Haptics Compatibility: agent entry point

## Start here

- Work from this repository, not a user's home directory or an archived clone.
- Read [current status](docs/STATUS.md), then [the document index](docs/INDEX.md).
- For code: read [architecture](docs/ARCHITECTURE.md) and [tests](docs/TESTING.md).
- For parallel work: read [coordination](docs/maintenance/MULTI_AGENT.md) and the assigned task.
- Check `git status --short --branch` and the task's baseline before editing.

## Native semantics are the contract

- The installed DST `haptics.lua` is the event source of truth. Historical counts
  such as 492/489 are snapshot facts, never hard-coded coverage targets.
- Preserve original fields, SoundEmitter arguments/returns and named-loop lifecycle.
- Require real client events or audited replicated confirmation. No button rumble,
  guessed Boss animations, gameplay RPCs, combat changes or save changes.
- Compatibility mode suppresses native output; Profile OFF, pause, disconnect and
  world exit must cancel output. Remain client-only and Lua 5.1 compatible.
- Separate exact event semantics from envelope/spatial/device approximations.
- Tests and device enumeration cannot prove physical motor response.

## Delegation and model choice

- Keep the primary chat's user-selected model, effort and speed. Do not change
  global settings, auto-switch it, or silently select a premium service tier.
- The user authorizes bounded delegation when it materially helps. Use no agents
  for a small serial change; normally at most two active children per coordinator.
- Preferred planning family: Astra, with high/xhigh/max only when warranted.
  Preferred implementation/review family: Sol, normally high; increase effort for
  demonstrated difficulty. Use model IDs actually offered by the current tool.
- Project custom agents are optional local-client presets, not a promise that every
  host exposes those role names. Use an explicit bounded prompt if unsupported.
- Read-only exploration may share a checkout. Parallel writers need distinct
  worktrees, branches and non-overlapping file ownership. Children do not recurse.
- Only the designated coordinator integrates, installs or publishes. Shared Git
  refs, tags, archives and release folders have one writer. See the coordination guide.

## Commands and evidence

```text
python tools/verify.py --report .local/evidence/<new-session>/verify.json
python tools/verify.py --lua-deps <DLL-directory> --original-scripts <current-scripts> --report <new-report.json>
pwsh -File tools/snapshot_game.ps1 -GameRoot <DST-directory> -ClientLog <client_log.txt>
pwsh -File tools/build_release.ps1 -OutputRoot build/<unique-session>
```

- `verify.py` owns the portable test list. Use Python 3.11+ and Lua 5.1 or the
  Windows `lua51Original.dll` route. Supply current native scripts explicitly.
- PASS, FAIL and SKIP are different. Record input hashes/build/date and actual
  commands. Missing native data is SKIP, never proof of native coverage.
- Use [the evidence index](docs/maintenance/EVIDENCE.md); preserve historical reports.
- Keep Klei scripts/WAVs, raw logs, local paths/config, archives and binaries out of
  commits. `.local/`, `archive/`, `work/`, `build/` and `outputs/` are ignored.
- `outputs/` keeps the last published release; development builds use a fresh path.
  Never rebuild over a release as a routine test. No automatic release/tag/Workshop upload.
- Use `codex/<task>` branches; preserve dirty work. Do not reset, force-push,
  delete worktrees or discard backups as cleanup. Archive with a hash/path manifest.

## Handoff

Use [the task template](docs/tasks/TEMPLATE.md) for meaningful multi-file work.
Return changed paths, base/completion commits, verification/report locations,
remaining risks and untested physical routes. Update status only for observed facts.
