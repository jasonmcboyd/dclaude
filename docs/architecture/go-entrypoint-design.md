# Go Entrypoint Architecture & Phased Roadmap

**Status:** Design / proposal — NOT implemented. Last updated 2026-06-14.

Roadmap for replacing `Entrypoints/entrypoint.sh` and `Entrypoints/entrypoint.ps1` with a single
compiled **Go** binary shipped in the runtime volume, reducing the PowerShell launcher
(`Invoke-DClaude.ps1`) to a thin client. See `platform-bootstrap.md` for the bootstrap contract
and the first principles (P1–P6) this addresses, and the project-memory
`project-entrypoint-mount-rework.md` for the decision history.

**Locked decisions** (see memory): Go (trivial cross-compile vs C# NativeAOT's no-cross-OS / Rust's
ceremony); sanitization moves INTO the binary, done in-container (kills both shell sanitizers and
all host-side delivery hacks); P5 Windows-profile probe stays launcher-side; keep the Windows
one-time symlink setup; scenarios 1 & 2 fully correct, scenario 3 = host-OS seam + flagged TODOs
only; binary ships via the runtime volume, built in CI on tag (local Go tooling not required to ship).

**Sanitizer posture: RATIFIED 2026-06-14 → fail-open denylist** (strip only `projects`/
`githubRepoPaths`, pass unknown Claude Code fields through). Rationale in §9. No open decisions remain.

---

## 1. Target Architecture Overview

### End state

Two collaborating components with a hard, narrow boundary:

- **Host launcher (PowerShell, thin):** `Invoke-DClaude.ps1` + the `Resolve-*` helpers. Only does
  what cannot be done from inside the container: detect container OS, detect host OS (new seam),
  resolve mount specs, probe the Windows profile path (P5), provision the runtime volume, assemble
  `docker run`. It no longer mounts/runs a shell script and knows nothing about `.claude.json`
  sanitization.
- **Go entrypoint binary (in the runtime volume):** Owns 100% of in-container bootstrap. PATH/
  COLORTERM, Linux user creation + UID match, git `safe.directory`, `.claude.json` sanitization
  (the single implementation), project session-count report, init.d execution, Docker CLI linking,
  privilege drop, and `exec claude`.

### Responsibility split

```
HOST (PowerShell launcher — thin client)
  Get-DockerContainerOS  -> containerOS (windows|linux)
  [NEW] Get-DClaudeHostOS -> hostOS (windows|linux|macos)   <- Sc-3 seam
  Resolve-ContainerPaths -> workspace path + mount specs
  [P5] Probe %USERPROFILE% (windows containers only)
  Initialize-RuntimeVolume -> volume w/ node + claude + ENTRYPOINT BINARY
  Build docker args: mounts + -e DCLAUDE_* + --entrypoint <runtime>/bin/dclaude-entrypoint
        |  docker run
        v
CONTAINER (Go binary — owns all bootstrap)
  PATH/COLORTERM | git safe.directory
  [linux] create claude user | UID match | setpriv/exec
  [windows] spawn claude.cmd
  SANITIZE .claude.json (ONE impl, fail-open denylist)
  session-count report | run init.d (shell out) | docker-cli link
  exec claude --dangerously-skip-permissions <args>
```

### Deleted

- Both shell sanitizers (`entrypoint.sh:59-91`, `entrypoint.ps1:28-80`) → one Go function.
- All host-side delivery hacks that were *considered but never built* (PowerShell hoist, sidecar,
  staged-file mount) — the in-container sanitize decision makes them unnecessary.
- Eventually `Entrypoints/entrypoint.sh` and `entrypoint.ps1` themselves, plus the entrypoint-mount
  and OneDrive-staging logic in `Invoke-DClaude.ps1:226-241,258-271,406-416`.

### Retained (launcher-side, survives the language change)

- `Resolve-ContainerPaths.ps1` mount resolution incl. the `/resume` project-dir bind (`:65-81`).
- The P5 Windows `%USERPROFILE%` probe (to be added).
- `Initialize-DClaudeWindowsContainers` one-time symlink setup.
- The runtime-volume provisioning model — the binary ships the same way node/claude do.

---

## 2. The Launcher ↔ Binary Contract

Load-bearing interface; both sides are versioned together via the runtime-volume version, so the
contract only needs to hold within one module version.

### 2.1 Mount layout the launcher guarantees

| Mount | Linux | Windows | Mode |
|---|---|---|---|
| Runtime volume (node + claude + **binary**) | `/opt/dclaude-runtime` | `C:\dclaude-runtime` | ro |
| Workspace | translated host path (`/c/Users/...`) | host path (`C:\...`) | rw |
| `~/.claude` directory | `/home/claude/.claude` | `C:/Users/<probed>/.claude` | rw |
| `.claude.json` source | nested RO in the dir mount | symlinked into the dir mount | ro |
| Project dir (`/resume`) | `/home/claude/.claude/projects/<key>` | `C:/.../projects/<key>` | rw bind |
| init.d dirs | `/mnt/init.d/...` | `C:/mnt/init.d/...` | ro |
| Docker CLI (opt-in) | `/opt/docker-cli` | `C:/docker-cli` | ro |

The binary reads these from env (below) with the current hardcoded values as fallbacks.

### 2.2 Environment contract

Existing (already emitted): `DCLAUDE_RUNTIME`, `DCLAUDE_WORKSPACE`, `DCLAUDE_HOST_PATH`,
`DCLAUDE_IMAGE`, `DCLAUDE_CONTAINER`, `DCLAUDE_VERBOSE`, `DCLAUDE_ENV`.

New:
- **`DCLAUDE_HOST_OS`** = `windows|linux|macos` — the scenario-3 seam (§7).
- **`DCLAUDE_CLAUDE_HOME`** = the `~/.claude` mount target (delivers the P5 probe result; replaces
  the binary guessing the Windows profile / `$env:USERPROFILE`).
- **`DCLAUDE_CONTRACT`** = integer contract version (e.g. `1`) — binary fails loud on a mismatched
  launcher.

### 2.3 Invocation

Replaces `Invoke-DClaude.ps1:258-271,406-416`:
```
--entrypoint <DCLAUDE_RUNTIME>/bin/dclaude-entrypoint       (Linux)
--entrypoint <DCLAUDE_RUNTIME>\bin\dclaude-entrypoint.exe   (Windows)
```
- Binary executes from the RO runtime mount (execve/CreateProcess need only read+execute; the Linux
  execute bit is set by the provisioner).
- Claude args go after the image, unchanged; the binary forwards `os.Args[1:]` verbatim to
  `claude --dangerously-skip-permissions`. The binary consumes no flags itself (all config via env).

### 2.4 Postconditions (unchanged bootstrap contract)

Tools on PATH; `~/.claude` read/write with host persistence; `.claude.json` sanitized; `/resume`
sees the real project dir; then `exec claude`.

---

## 3. Go Binary Design

### 3.1 Repo layout

```
go.mod                         module github.com/jasonmcboyd/dclaude  (go 1.22+)
cmd/dclaude-entrypoint/main.go # arg passthrough, env read, dispatch by GOOS
internal/bootstrap/            # orchestration, typed env, [dclaude] logging + FATAL
internal/sanitize/             # the ONE .claude.json transform (+ unit tests, no docker)
internal/initd/                # discover + shell out to init scripts
internal/platform/
  platform.go                  # shared interface
  platform_linux.go            # //go:build linux  — user create, UID match, setpriv/exec
  platform_windows.go          # //go:build windows — spawn claude.cmd
```

Platform code uses `//go:build` constraints (not `runtime.GOOS` switches) so each cross-compiled
binary contains only its own platform code. The scenario-3 host distinction is a *runtime*
`DCLAUDE_HOST_OS` check inside `platform_linux.go` (scenarios 2 and 3 are the same Linux binary).

### 3.2 Step → fatality mapping

Fatal: Linux user creation; `.claude.json` parse error; the final exec. Best-effort (warn,
continue): PATH/git/COLORTERM, UID match, session report, each init.d script, docker-CLI link,
home chown, docker-group add.

### 3.3 Per-platform notes

- **Linux:** shell out to `useradd`/`adduser` (pure-Go `os/user` can't create users); UID match via
  `stat` + `usermod` (gated by `DCLAUDE_HOST_OS`, §7); shell out to `setpriv` with byte-identical
  flags (the ambient-cap/WSL2-timestamp behavior is subtle — do NOT reinvent); final hand-off via
  **`syscall.Exec`** (replaces shell `exec`; fixes signal propagation — better than today).
- **Windows:** spawn `claude.cmd` via `exec.Command`, inherit stdio, propagate exit code (same
  PID-1-child limitation the doc already records; cleaner, since the parent is now a tiny native
  process). Docker-plugin symlinks via `os.Symlink`. Profile from `DCLAUDE_CLAUDE_HOME`.

### 3.4 The sanitizer (recommend fail-open denylist)

Decode into `map[string]json.RawMessage` (a typed struct would silently drop unknown keys — the P6
failure mode). Transform: capture MCP fields from the host project entry (matched by
`DCLAUDE_HOST_PATH` + forward-slash variant); delete only `projects` and `githubRepoPaths`; force
the two marketplace flags true; recreate `projects` with one entry keyed by `DCLAUDE_WORKSPACE`
(`allowedTools: []`, `hasTrustDialogAccepted: true`, `...preservedMCP`). **Run unconditionally every
start** (fixes the Windows staleness bug). Parse failure is fatal; missing source is best-effort.
Keep writing to the ephemeral home location for the initial cutover (persisting sanitized writes is
a separate, post-cutover decision that interacts with P3 un-nesting — §9).

### 3.5 init.d execution

Shell out (`sh -c` for `*.sh`, `powershell -NoProfile -File` for `*.ps1`). Deliberate behavior
change: scripts run as subprocesses, **not sourced** (`entrypoint.sh:113` sources them) — a Go
parent can't offer in-process sourcing, and the current sourcing is itself a P1 landmine. Per-script
failures become warnings. If env-mutation is ever needed, add an export-file convention.

### 3.6 Error strategy (satisfies P1 by construction)

No global `set -e` / `$ErrorActionPreference='Stop'` — Go has no implicit abort, so the
"every line is a landmine" class cannot exist. Each step's fatality is explicit; FATAL logs
`[dclaude] FATAL: <step>: <err>` and exits 1, best-effort logs `[dclaude] WARN` and continues.

---

## 4. Build & Ship Pipeline

### 4.1 Cross-compile matrix (single `ubuntu-latest` runner)

`linux/amd64`, `linux/arm64`, `windows/amd64`, `windows/arm64`; `CGO_ENABLED=0` everywhere (all
external tools are subprocesses, never linked) → no libc dependency, so the glibc/musl split that
blocks Node.js does not apply to the binary (it would even run on Alpine; Alpine stays unsupported
only because of Node.js).

### 4.2 CI (`.github/workflows/publish-release.yml`)

Add a `build-entrypoint` job before `publish`, gated on the `v*` tag: `setup-go` → `go test ./...`
→ matrix `go build -trimpath -ldflags "-s -w -X main.version=<tag>"` → attach the four binaries as
GitHub Release assets. The `publish` job gains `needs: build-entrypoint`, so a binary build/test
failure blocks the module publish.

### 4.3 Provisioning download (same way node/claude are)

`New-RuntimeVolume.ps1` already curls node and npm-installs claude *inside the provisioning
container* (`:76,90`). Add one `curl` per platform to fetch the matching release asset into
`/out/bin/dclaude-entrypoint` (`chmod +x` on Linux). Version `__VER__` = the module version, injected
like `__NODE__`/`__CLAUDE__`, so binary version = runtime-volume version = module version (one axis,
no drift). Add the binary to the populated-check (`Test-RuntimeVolumePopulated`). Local dev escape
hatch: `DCLAUDE_ENTRYPOINT_SRC` → `docker cp` a locally built binary (never used in the ship path).

---

## 5. Launcher Changes

**Stays:** mount resolution, `Get-DockerContainerOS`, image/volume/env assembly,
`Initialize-RuntimeVolume`, `Update-RuntimeIfOutdated`, `Remove-StaleRuntimeVolumes`,
`Initialize-DClaudeWindowsContainers`.

**Changes:** replace the entrypoint mount + `--entrypoint /bin/sh|powershell` with
`--entrypoint <runtime>/bin/dclaude-entrypoint[.exe]`; remove the OneDrive entrypoint-staging block
(`:233-241`, now dead — no host-side entrypoint mount); remove `$entrypointsDir` resolution
(`:226-231`); add `Get-DClaudeHostOS` + emit `DCLAUDE_HOST_OS`; add the P5 `%USERPROFILE%` probe +
emit `DCLAUDE_CLAUDE_HOME`; emit `DCLAUDE_CONTRACT=1`.

**Deleted (final phase):** `Entrypoints/*`, the `Copy-Item ./Entrypoints` in
`create-module-manifest.ps1:22`.

**Loss of hot-edit:** mitigated by `go test ./...` (faster than any container loop) + local
`docker cp` injection. Net testability improves (the sanitizer becomes unit-testable for the first
time).

---

## 6. First-Principles Coverage

| Item | How Go addresses it | Status |
|---|---|---|
| P0 Tools on PATH | Unchanged mechanism | Preserved |
| **P1 Silent-abort** | No `set -e`/`Stop`; explicit per-step fatal/best-effort | **Solved by construction** |
| P2 Linux UID | Reimplemented + `DCLAUDE_HOST_OS`-gated; `usermod`-absent warns not crashes; real `--user` fix is launcher/Sc-3 | Partial |
| P3 RO-nested file | Defused (a binary reading an RO mount isn't a `set -e` landmine); un-nesting now optional | Defused |
| P4 Win file-mount/symlink | Unchanged; one-time symlink retained | Unchanged (accepted) |
| **P5 Win profile coupling** | Solved launcher-side via probe → `DCLAUDE_CLAUDE_HOME` | Solved |
| **P6 Sanitizer drift/dup** | One Go impl; recommended fail-open denylist | Solved (pending posture) |
| Bug: Win sanitizer staleness | Fixed — sanitize unconditionally | Fixed |
| Bug: ephemeral sanitized file | Not changed in cutover (de-risk); easy later fix | Carried, flagged |

P1 and P6 (the two strongest motivations) are solved by construction; P3 defused; P5 solved
launcher-side; P2/P4 unchanged/partial and remain launcher concerns.

---

## 7. Scenario-3 Seam + Flagged TODOs

New `Get-DClaudeHostOS.ps1` (`$IsWindows`/`$IsLinux`/`$IsMacOS`, `'windows'` fallback on PS 5.1);
launcher emits `DCLAUDE_HOST_OS`. This is the only new host-OS branch and changes no existing
behavior. In `platform_linux.go`, the UID-match switch treats `windows`/`macos` as scenario 2 (FUSE
→ no-op), and `linux` as a `// TODO(scenario-3)` branch that replicates today's untested
`entrypoint.sh:44-52` behavior verbatim with a verbose marker — no NEW behavior, nothing untestable
shipped. Future scenario-3 work (native-Linux `--user`, root-owned-workspace, `usermod`-absent) has
an obvious home there.

---

## 8. Migration Plan

**Hard cutover at a single module version**, not a dual shell+binary path (which would double the
maintenance surface the rewrite eliminates). The runtime volume is version-pinned, so old versions
keep their shell entrypoints + old volumes untouched; the first Go version provisions a fresh volume
(new name) containing the binary, and `Remove-StaleRuntimeVolumes` reclaims the old. The version axis
IS the rollback (pin the prior module version). Do NOT keep shell entrypoints as a runtime fallback —
a missing binary is a broken volume that should fail loud and re-provision.

During development, a `DCLAUDE_USE_GO_ENTRYPOINT` flag (default off) lets the binary path be
exercised while the shell path still ships; removed at cutover. Existing users: re-provision happens
automatically on the version bump (first run slower, as on any bump); Windows symlink setup needs no
re-run; host `~/.claude` unchanged. `Entrypoints/` deleted in the final phase.

---

## 9. Risks + Open Decisions

- **Sanitizer posture (RATIFIED 2026-06-14 → fail-open denylist):** Baseline threat model is
  host-with-`--dangerously-skip-permissions`; this is the user's own config into their own container.
  Fail-closed's cost is *silent* breakage when CC adds a field; the denylist's only downside is a
  theoretical future host-specific key leaking a host path (trivially extensible; `projects`/
  `githubRepoPaths` are the only known offenders). **Flag for explicit sign-off before `sanitize.go`.**
- **Provisioning download dependency:** offline / 404 asset fails provisioning — but node/claude have
  the same exposure today, so same-tier, not a new class. Fail loud naming the binary; `docker cp`
  escape hatch for devs.
- **Loss of hot-edit:** real DX cost, mitigated by `go test` + local injection; net testability up.
- **Exec from RO volume:** low risk; only needs read+execute; execute bit set at download.
- **Riskiest change to working scenarios:** Sc2 — the `setpriv` privilege-drop reimplementation
  (shell out with byte-identical flags; focus the smoke test here). Sc1 — losing OneDrive staging is
  safe (binary isn't host-mounted; the runtime *volume* isn't OneDrive-backed).
- **init.d sourcing → subprocess:** minor behavior change (env-mutating init scripts no longer work
  in-process); note in release notes.
- **Ephemeral sanitized file / `lastSessionId` loss:** pre-existing; deliberately not fixed in the
  cutover; fast-follow (interacts with P3 un-nesting).

---

## 10. Phased Roadmap

Each phase is independently shippable and verifiable on a Windows host without scenario-3 hardware.
Phases 1–5 ship behind `DCLAUDE_USE_GO_ENTRYPOINT` (default off); P6 flips the default and deletes
the shell path.

1. **Scaffold Go module + Linux parity (flag-gated).** `go.mod`, `cmd/dclaude-entrypoint`,
   `internal/{bootstrap,sanitize,initd,platform}` (Windows stub). Verify: `go test ./...` on the
   sanitizer with real `.claude.json` fixtures; build linux/amd64, `docker cp` into a scratch volume,
   run scenario 2 with the flag on.
2. **CI build matrix + release assets.** Extend `publish-release.yml`. Verify with a throwaway
   prerelease tag (four assets attach, `go test` runs). No container needed.
3. **Provisioning download.** Extend `New-RuntimeVolume.ps1` (`:76,90`) + `Test-RuntimeVolumePopulated`;
   optional `DCLAUDE_ENTRYPOINT_SRC`. Verify: delete local volumes, run, confirm `bin/dclaude-entrypoint`
   present + executable + boots. Pester tests for provisioning-string assembly.
4. **Launcher invocation switch (Linux).** `Invoke-DClaude.ps1` entrypoint logic + new env vars;
   `Get-DClaudeHostOS.ps1`. Verify: Pester arg assertions; scenario-2 end-to-end (PATH, sanitize,
   `/resume`, credential persistence via a marker write).
5. **Windows parity + P5 probe.** `platform_windows.go`; launcher probe → `DCLAUDE_CLAUDE_HOME`;
   `Resolve-ContainerPaths.ps1` consumes the probed profile (drops the `ContainerAdministrator`
   hardcode `:25`). Verify scenario 1: boots via binary, re-sanitizes on restart (staleness fixed),
   `/resume`, docker-plugin links, non-default-user image.
6. **Cutover + delete shell entrypoints.** Flip the flag default, then remove it; delete
   `Entrypoints/*`, the staging code, the `Copy-Item ./Entrypoints`; update `CLAUDE.md` and
   `platform-bootstrap.md`. Verify full scenarios 1 & 2 regression against the must-not-regress
   contract; tag a real release; confirm clean provisioning from empty Docker state. Scenario 3
   remains a flagged seam, untested by design.
