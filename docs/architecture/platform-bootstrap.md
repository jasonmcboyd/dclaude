# Platform Bootstrap Architecture

**Canonical reference for container bootstrap mechanics across all three deployment scenarios.**
Last updated: 2026-06-13. Status of each item reflects the current codebase; see §6 for planned
rework.

---

## 1. Purpose and the Bootstrap Contract

The entrypoint's job is to satisfy a platform-agnostic contract before handing control to Claude
Code:

| Postcondition | What it means |
|---|---|
| **Tools on PATH** | `node`, `claude`, `git` are executable in the container's PATH |
| **Credentials readable and writable** | `~/.claude/` and everything inside it can be read and written atomically by Claude Code; writes persist to the host |
| **`.claude.json` sanitized** | The file at `~/.claude.json` inside the container has had host-specific paths stripped, the container workspace pre-accepted, and marketplace prompts suppressed |
| **Config round-trip** | Claude Code can read and write `~/.claude.json`; changes survive the session (so `lastSessionId` and MCP auth tokens persist to the next run) |
| **`/resume` sees prior sessions** | `~/.claude/projects/<container-key>/` is a real bind-mount directory containing `.jsonl` transcript files; Claude Code's `readdir({withFileTypes:true})` returns `isDirectory()=true` for it |

The runtime-volume injection (tools on PATH) satisfies its postcondition cleanly and is not a
source of brittleness. The remaining postconditions — credential sharing, sanitization, and resume
— each have platform-specific complications documented below.

---

## 2. The Substrate Problem

### Why one implementation cannot serve all three scenarios

The two entrypoints (`entrypoint.sh`, `entrypoint.ps1`) differ not just in syntax but in the
underlying filesystem substrate they operate on:

| Scenario | Container OS | Host substrate | Ownership model |
|---|---|---|---|
| 1. Windows containers on Windows host | Windows | NTFS (Hyper-V isolation) | ACLs; `ContainerAdministrator` default user |
| 2. Linux containers on Windows host | Linux | Docker Desktop FUSE translation layer | UID/GID synthesized; no real POSIX inode |
| 3. Linux containers on Linux host | Linux | Real POSIX bind mount | Real UID/GID from host kernel |

These substrate differences are the root cause of every fragility item in §4.

### The critical single-axis branch: containerOS, not hostOS

**The launcher (`Invoke-DClaude.ps1`) keys all branching exclusively off `$containerOS`**, which
comes from `Get-DockerContainerOS` (`docker info --format '{{.OSType}}'`). There is no host-OS
detection in `src/` — no `$IsWindows`, `$IsLinux`, `$IsMacOS`, no `uname`, no
`RuntimeInformation` checks anywhere in the module source.

Verified by grep: the only `uname` occurrences in `src/` are inside shell strings passed as
provisioning scripts to `docker run` inside containers (`New-RuntimeVolume.ps1` line 76,
`Initialize-DockerCliVolume.ps1` line 33) — they detect the container's CPU architecture, not
the host OS.

**Consequence:** Scenarios 2 and 3 are **code-identical from the launcher's perspective**. They
execute the same `Invoke-DClaude.ps1` branches, call the same `ConvertTo-ContainerPath`, and
invoke the same `entrypoint.sh`. Scenario 3 has never been tested. Every claim about scenario 3
in this document is a prediction from code analysis; it is labeled **UNVERIFIED**.

The OneDrive entrypoint staging block (lines 233–240 of `Invoke-DClaude.ps1`) is the one
Windows-host-only behavior that runs today, but it is gated on `$containerOS -eq 'windows'` —
the windows-container scenario — so it doesn't affect scenarios 2 or 3 regardless of host OS.

---

## 3. Matrix: First Principles vs. Scenarios

Status markers: ✅ works | ⚠️ works-but-fragile | ❌ broken-or-unhandled | ❓ UNVERIFIED

| Principle | Sc 1: Win containers / Win host | Sc 2: Linux containers / Win host | Sc 3: Linux containers / Linux host (UNVERIFIED) |
|---|---|---|---|
| **P0. Tools on PATH** (runtime volume) | ✅ Clean | ✅ Clean | ❓ Same code path; predicted clean |
| **P1. Silent-abort landmines** | ⚠️ `try/catch` covers first block; tail runs unprotected | ⚠️ `set -e` throughout; `|| true` guards only the `chown` | ❓ Same as Sc 2 |
| **P2. Linux ownership / UID** | ✅ N/A (Windows; ACLs) | ⚠️ UID 1000 hardcoded; dynamic match only triggers when `ws_uid` ≠ 0 and ≠ 1000 | ❓ Same code; predicted to work IF host UID happens to be 1000; mismatch causes permission errors |
| **P3. RO file nested in RW tree** | ✅ Avoided (symlink travels with dir mount; no nested bind) | ⚠️ `.claude.json:ro` is a nested bind inside the RW `.claude` mount; currently guarded only in `chown` | ❓ Same as Sc 2 |
| **P4. Windows file / symlink limits** | ⚠️ Single-file bind impossible; requires one-time `Initialize-DClaudeWindowsContainers`; `SeCreateSymbolicLinkPrivilege` required | ✅ N/A (Linux containers use normal bind mounts) | ✅ N/A |
| **P5. Windows image-default-user coupling** | ⚠️ Mount target hardcoded to `ContainerAdministrator`; silently wrong for other images | ✅ N/A (Linux path `/home/claude/.claude` is created by entrypoint) | ✅ N/A |
| **P6. `.claude.json` sanitizer allowlist drift** | ⚠️ Hand-maintained allowlist; fail-closed on unknown CC schema fields; duplicated in `.ps1` | ⚠️ Same allowlist duplicated in `.sh`; same fail-closed risk | ❓ Same as Sc 2 |
| **`/resume` project dir bind mount** | ✅ Bind mount via `Resolve-ContainerPaths.ps1` | ✅ Same | ❓ Same code; predicted to work if path translation is correct |

---

## 4. Per-Principle Detail

### P0. Tools on PATH — the clean part

**Requirement:** `node`, `claude`, `git` must be executable inside the container without
requiring any tooling to be baked into the image.

**How it works (all scenarios):**
- `Initialize-RuntimeVolume.ps1` lazily provisions a named Docker volume
  (`dclaude-runtime-{os}-v{version}-r{N}`) containing Node.js, Claude Code, and MinGit (Windows
  only). The provisioning script in `New-RuntimeVolume.ps1` detects container CPU architecture
  via `uname -m` inside the provisioning container itself (not the host).
- Mounted read-only at `/opt/dclaude-runtime` (Linux) or `C:\dclaude-runtime` (Windows).
- Entrypoint line 5–6 (`entrypoint.sh`) / lines 8–9 (`entrypoint.ps1`) prepend the runtime
  `node/bin` directory to PATH.
- `DCLAUDE_RUNTIME` env var lets the entrypoint find the mount path without hardcoding it.

**Gaps:** None in the core mechanism. Alpine images (musl libc) cannot use the glibc-linked
Node.js binary; this is documented in CLAUDE.md as a known limitation.

---

### P1. Silent-abort landmines

**Requirement:** Best-effort steps (git config, chown, init scripts) must not abort the
entrypoint. Fatal steps (sanitizer failure, PATH setup) should abort loudly with a message.

#### Scenario 1 (Windows containers)
`$ErrorActionPreference = 'Stop'` is set at the top of `entrypoint.ps1` (line 1). The first
logical block (lines 4–100) is wrapped in a single `try/catch` that prints a FATAL message and
exits on any error. **However**, the rest of the script — Docker CLI setup (lines 102–118), init
scripts (lines 120–136), and the final `claude.cmd` invocation (lines 138–143) — runs **after**
the closing `}` of that `try` block, still under `$ErrorActionPreference = 'Stop'` with no
further protection. Init scripts explicitly catch and warn (`lines 127–132`), but Docker CLI
symlink creation uses `New-Item -ItemType SymbolicLink ... -Force` without a try/catch; a
privilege failure there would terminate the entrypoint without a useful message.

`$ErrorActionPreference` is reset to `Continue` at line 141 only immediately before the final
`& claude.cmd`, which protects that call but not the steps between lines 100 and 141.

#### Scenario 2 (Linux containers on Windows host)
`set -e` is active throughout `entrypoint.sh` (line 2). Protections present:
- User creation (line 18): ends with `|| true`
- `chown` recursive (line 147–148): ends with `|| true` with an explicit comment about the
  RO-nested-file risk
- Init scripts (line 109–113): called with `. "$script"` under `set -e`; a failing init script
  aborts the entrypoint (no protection)
- Docker CLI symlink (line 120–127): `ln -sf` failures under `set -e` are fatal

The sanitizer failure path (lines 87–90) correctly uses `exit 1` after an explicit FATAL message,
which is correct behavior.

#### Scenario 3 (Linux containers on Linux host)
UNVERIFIED. Same `entrypoint.sh`; same risks as Scenario 2.

**Known gaps:** The init-script execution pattern (`. "$script"`) in `entrypoint.sh` is
unprotected by `set -e`. A failing init script terminates the entrypoint without a clear source
message. The Windows entrypoint does catch init script errors (lines 127–132) and warns rather
than terminating.

---

### P2. Linux ownership / UID

**Requirement:** The `claude` user inside the container must be able to read and write files in
the workspace. On a Linux host with a real POSIX mount, the container UID must match the host
UID or the user running the container gets `EACCES` on their own files.

#### Scenario 1 (Windows containers)
Not applicable. Windows containers use NTFS ACLs. The `ContainerAdministrator` user has
full access to mounted directories. No UID concept.

#### Scenario 2 (Linux containers on Windows host)
`entrypoint.sh` lines 44–52: runs a dynamic UID-match block **only when the entrypoint
is already running as root (UID 0)**. It stats the workspace to get `ws_uid`, then calls
`usermod -u "$ws_uid" claude` if `ws_uid` is neither `0` nor `1000`.

The WSL2 skip condition (`ws_uid = 0`) is the documented heuristic for detecting Docker Desktop's
9P mount, where workspace files appear root-owned. **This heuristic is substrate-dependent:** on
Docker Desktop for Windows, workspace files typically appear as UID 0, so the dynamic match block
is skipped and `claude` remains at the hardcoded UID 1000. In practice this works because Docker
Desktop's FUSE layer synthesizes ownership, making UID mismatches transparent.

The fallback `|| echo "1000"` in `stat` (line 47) means `ws_uid` defaults to 1000 if `stat`
fails, which skips the `usermod` call — safe default.

#### Scenario 3 (Linux containers on Linux host) — UNVERIFIED
On a native Linux host, workspace files appear with the **real host UID**. If that UID is not 0
and not 1000, the dynamic match triggers and `usermod -u "$ws_uid" claude` adjusts the claude
user. This is the intended behavior for native Linux. **However:**
- If the host UID is 1000 (common default), `claude` stays at 1000 — correct by coincidence.
- If the host UID is 0 (root), the skip condition fires and `claude` remains at 1000 — files
  owned by root in the workspace will be unwritable after privilege drop.
- There is no recursive `chown` on the workspace itself; ownership is not corrected retroactively.
- `usermod` may not exist in all stock images (`busybox`-based or minimal images may lack it);
  the `adduser -D` fallback in line 18 does not have a corresponding UID-change equivalent.

The `find ... chown` block (lines 147–148) fixes ownership of `/home/claude`, not the workspace.

---

### P3. Read-only file nested in a read-write tree

**Requirement:** `.claude.json` must be readable and writable inside the container so that
Claude Code's `--continue`, MCP token refreshes, and metrics writes all persist.

#### Scenario 1 (Windows containers)
`Initialize-DClaudeWindowsContainers` moves `~/.claude.json` into `~/.claude/.claude.json`
on the host and replaces it with a symlink (`Initialize-DClaudeWindowsContainers.ps1` lines
46–49). The directory mount (`~/.claude`) carries the file with it, so `.claude.json` travels
as part of the read-write directory bind — **no nested read-only mount**. The entrypoint reads
from `$claudeDir\.claude.json` and writes the sanitized version to `$claudeJson`
(`$env:USERPROFILE\.claude.json`), which is inside the container user's profile, unrelated to
the mount.

Windows avoids the nested-RO problem structurally.

#### Scenario 2 (Linux containers on Windows host)
`Resolve-ContainerPaths.ps1` lines 43–54 mount `~/.claude.json` as a **separate nested
read-only bind** inside the `~/.claude` read-write mount:

```
-v ~/.claude:/home/claude/.claude:rw
-v ~/.claude.json:/home/claude/.claude/.claude.json:ro
```

The entrypoint reads from `/home/claude/.claude/.claude.json` (the RO source) and writes the
sanitized result to `/home/claude/.claude.json` (outside the directory mount, in the container
user's home). That write path is in the container filesystem, not on the host — the sanitized
version is ephemeral.

The RO nested bind creates a landmine for any operation that tries to recursively `chown` or
`chmod` the `.claude` directory. The current `find ... -prune` guard (line 147–148 of
`entrypoint.sh`) explicitly excludes `/home/claude/.claude/.claude.json` from the chown sweep.
This works, but any new recursive operation that doesn't replicate the prune pattern will hit an
`EPERM` and — under `set -e` — silently abort the entrypoint unless protected with `|| true`.

The sanitized `.claude.json` at `/home/claude/.claude.json` is written by the entrypoint
(line 87) and **is writable**, but it is outside the bind-mounted `~/.claude` directory and
thus does not persist to the host. Per the bootstrap contract, config round-trip requires that
writes to `~/.claude.json` survive the session.

> **Discrepancy from CLAUDE.md:** CLAUDE.md states "The Linux entrypoint reads from
> `~/.claude/.claude.json` (inside the direct mount) and writes the sanitized version to
> `~/.claude.json`." This is accurate as a description of what the entrypoint does, but it
> implies the write persists. The write target (`/home/claude/.claude.json`) is **not** inside
> the bind-mounted `~/.claude` directory and therefore does **not** persist to the host. The
> sanitized file is recreated fresh each container run from the RO source. This is intentional
> (the host file stays pristine), but means `lastSessionId` and any metric writes by Claude Code
> to `.claude.json` during the session are lost when the container exits.

#### Scenario 3 (Linux containers on Linux host) — UNVERIFIED
Same `entrypoint.sh` and same `Resolve-ContainerPaths.ps1` path. Predicted identical to
Scenario 2: the nested-RO mount exists, the prune guard protects the chown, and the sanitized
write does not persist. The UID situation (§P2) could additionally cause `EACCES` on the write
to `/home/claude/.claude.json` if ownership is wrong.

---

### P4. Windows file-level bind mount impossibility and symlink privilege

**Requirement:** `~/.claude.json` must reach the container. Windows containers cannot bind-mount
individual files (only directories).

#### Scenario 1 (Windows containers)
The workaround is a one-time host-side operation: `Initialize-DClaudeWindowsContainers`
(`Initialize-DClaudeWindowsContainers.ps1`) moves `~/.claude.json` into `~/.claude/` and
replaces it with a symlink. **Prerequisites:**
- Requires `SeCreateSymbolicLinkPrivilege` (granted by running as administrator or enabling
  Developer Mode in Windows Settings).
- `Resolve-ContainerPaths.ps1` lines 45–49 check that the symlink is in place before the
  container starts and add an error to `$errors` if it is not.
- Symlinks also break Claude Code's `/resume` (`readdir({withFileTypes:true})` returns
  `isDirectory()=false` for symlinks), so the project-dir mount (`lines 65–81` of
  `Resolve-ContainerPaths.ps1`) uses a real bind mount, not a symlink.

The Windows entrypoint (`entrypoint.ps1` lines 102–117) creates symlinks for Docker CLI plugins
inside the container using `New-Item -ItemType SymbolicLink`. This succeeds because the
container's default user (`ContainerAdministrator`) has the required privilege in Windows Server
containers.

#### Scenarios 2 and 3 (Linux containers)
Not applicable. Linux containers support file-level bind mounts natively.

---

### P5. Windows image-default-user coupling

**Requirement:** Mounts must land in the correct user profile directory inside the container.

#### Scenario 1 (Windows containers)
`Resolve-ContainerPaths.ps1` line 25 hardcodes the mount target:

```powershell
$claudeHome = 'C:/Users/ContainerAdministrator/.claude'
```

This is the profile path for the default user in Microsoft's official Windows Server / Nano Server
images. It will be **silently wrong** for:
- Any image whose default user has a different username
- Any image run with an explicit `--user` flag

There is no mechanism to derive the profile path from the image's actual running user. The
Windows entrypoint also hardcodes `$env:USERPROFILE` in lines 14–15, which resolves correctly
at runtime inside the container — but only because the launcher already mounted the directory
at the right path for `ContainerAdministrator`.

The containerised Docker CLI symlinks in `entrypoint.ps1` (lines 109–111) use
`$env:USERPROFILE\.docker\cli-plugins`, which is dynamic and correct at runtime.

#### Scenarios 2 and 3 (Linux containers)
The mount target `/home/claude/.claude` is hardcoded in `Resolve-ContainerPaths.ps1` line 28,
but the `claude` user is **created by the entrypoint** (lines 12–19 of `entrypoint.sh`), so
the username is always `claude` regardless of the base image. This is self-consistent and robust
in practice, though it means the container always runs as `claude` rather than the image's
intended user.

---

### P6. `.claude.json` sanitizer allowlist drift

**Requirement:** The sanitizer must strip host-specific fields (workspace paths, GitHub paths),
preserve fields Claude Code needs in the container (MCP config), and pass through everything else
without silently dropping it.

**The shared logic** (both entrypoints do this identically):
1. Delete `projects` (host paths)
2. Delete `githubRepoPaths` (host-specific)
3. Set `officialMarketplaceAutoInstallAttempted` and `officialMarketplaceAutoInstalled` to `true`
4. Re-create `projects` with the container workspace pre-accepted and MCP fields
   (`mcpServers`, `mcpContextUris`, `enabledMcpjsonServers`, `disabledMcpjsonServers`) preserved
   from the matching host project entry

**The allowlist problem:** The MCP field list is a hand-maintained constant in both
`entrypoint.sh` (lines 65–66) and `entrypoint.ps1` (line 43). Claude Code's per-project schema
is undocumented and evolves across releases. Any new field Claude Code adds to the project entry
is silently dropped (fail-closed). The risk is that new session-critical fields — for example a
future `lastSessionId` or additional auth state — are silently stripped, causing subtle
misbehavior with no error message.

**The duplication problem:** The same transform is implemented in two languages in two files.
They can drift. A field preserved in `entrypoint.sh` but not in `entrypoint.ps1` (or vice versa)
creates a scenario-specific behavioral difference that is difficult to detect in testing.

**Scenario 1 (Windows containers):** Sanitizer runs in PowerShell (`ConvertFrom-Json` /
`ConvertTo-Json`). Conditional: only runs if `.claude.json` does not already exist at the
destination (`-not (Test-Path $claudeJson)`, line 33 of `entrypoint.ps1`). This means
**on container restart the sanitizer does not re-run** — the stale sanitized file from the
previous run is reused. Implication: if the host `.claude.json` is updated between runs
(e.g., new MCP credentials), the container sees the old sanitized version.

**Scenario 2 (Linux containers on Windows host):** Sanitizer runs via `node -e` (lines 59–91 of
`entrypoint.sh`). Runs unconditionally on every container start — the sanitized output is always
fresh. This is the correct behavior for credential freshness.

**Scenario 3 (Linux containers on Linux host) — UNVERIFIED:** Same `entrypoint.sh`; predicted
to behave the same as Scenario 2.

---

## 5. Per-Scenario Summary

### Scenario 1: Windows containers on Windows host

**State of the world:** Works for users who have run `Initialize-DClaudeWindowsContainers` and
have `SeCreateSymbolicLinkPrivilege`. The entrypoint staging to `$LOCALAPPDATA` (lines 233–240
of `Invoke-DClaude.ps1`) prevents OneDrive reparse points from blocking Hyper-V bind mounts.

Primary risks:
- The `ContainerAdministrator` hardcode (P5) silently breaks non-standard images
- The sanitizer only runs once per destination file lifetime (P6); stale sanitized credentials
  on restart
- `$ErrorActionPreference = 'Stop'` protection gap between lines 100 and 141 of `entrypoint.ps1`
  (P1)
- Requires privileged one-time host setup for the symlink; setup failure gives a clear error
  from `Resolve-ContainerPaths.ps1` but only at container start time

### Scenario 2: Linux containers on Windows host

**State of the world:** The primary tested and exercised scenario. Functions correctly in
practice. The FUSE ownership model on Docker Desktop neutralizes the UID mismatch problem (P2)
that would be dangerous on a real Linux host.

Primary risks:
- Nested RO bind of `.claude.json` inside the RW `.claude` mount (P3); guarded today in chown,
  but any future recursive operation needs its own guard
- Init script failures abort the entrypoint under `set -e` with no source attribution (P1)
- Sanitizer allowlist drift (P6)
- The sanitized `.claude.json` written by the entrypoint does not persist to the host; session
  metrics and `lastSessionId` are lost on container exit

### Scenario 3: Linux containers on Linux host — NEVER TESTED

> **All claims below are predictions from code analysis. This scenario has never been run.
> Do not assume any of it works.**

`Invoke-DClaude.ps1` on a Linux host runs via `pwsh`. `Get-DockerContainerOS` runs
`docker info --format '{{.OSType}}'`, which returns `linux`. All `$containerOS -eq 'linux'`
branches fire — same as Scenario 2. The launcher emits the same `docker run` argument list.

**Predicted first failures:**

1. **`ConvertTo-ContainerPath` misidentifies Linux host paths as already-translated.**
   `ConvertTo-ContainerPath.ps1` line 14 pattern-matches on `^([A-Za-z]):(.*)` to detect
   Windows drive letters. A Linux path (`/home/user/project`) does not match this pattern, so
   it is returned as-is (line 27 fallback). This is **correct behavior for a Linux host** —
   no translation needed, because the host path is already a valid Linux path. However, no test
   has verified this end-to-end.

2. **UID mismatch is the most likely first failure** (P2). On a real Linux host, workspace files
   have real UIDs. If the host user's UID is not 1000 and not 0, `usermod -u "$ws_uid" claude`
   fires. This is the intended behavior, but `usermod` may not exist in minimal images. If the
   host UID is 0 (root running Docker), the skip condition fires and `claude` at UID 1000 cannot
   write to root-owned workspace files.

3. **`$HOME` on a Linux host with PowerShell.** `Invoke-DClaude.ps1` uses `$HOME` for
   `$ClaudeConfigPath` default (line 75). In `pwsh` on Linux, `$HOME` is the standard Unix
   home directory (e.g., `/home/user`). `Resolve-ContainerPaths.ps1` uses `$ClaudeConfigPath`
   to locate `~/.claude` and `~/.claude.json`. This should work correctly — but is untested.

4. **OneDrive staging block does not run** (it is gated on `$containerOS -eq 'windows'`), so
   that Windows-specific path is correctly skipped.

5. **Entrypoint search path.** `Invoke-DClaude.ps1` lines 228–231 find `entrypointsDir` by
   navigating up from `$PSScriptRoot`. On a Linux installed module, `$PSScriptRoot` is a Linux
   path; `Split-Path` works cross-platform in `pwsh`. Predicted to work.

6. **The nested-RO `.claude.json` mount** is assembled by `Resolve-ContainerPaths.ps1` using
   string interpolation on `$ClaudeConfigPath` and `$claudeJsonPath`. On a Linux host these are
   already Linux paths, passed directly to `docker run -v`. Predicted to work, but the same P3
   fragility exists as in Scenario 2.

---

## 6. Planned Rework

These are directions established in analysis (see project memory `project-entrypoint-mount-rework.md`).
None are implemented.

| Item | Direction |
|---|---|
| **P1: Silent-abort landmines** | Wrap best-effort steps in `|| true` (sh) or `try/catch { Write-Warning }` (ps1); add an explicit `trap` at the end of the Windows entrypoint tail |
| **P2: UID alignment** | Already partially handled by the `stat` + `usermod -u` block (`entrypoint.sh:44-52`). Refinements: handle images lacking `usermod`; handle a root-owned workspace on a native Linux host (currently leaves `claude` at 1000); optionally replace the in-entrypoint `usermod` with `--user $(id -u):$(id -g)` from the launcher on Linux hosts (requires host-OS detection, which doesn't exist yet). On Docker Desktop (Windows host) the block correctly skips — UID matching is meaningless there |
| **P3: Un-nest the RO file** | Mount `.claude.json` at a path outside `~/.claude` (e.g., `/mnt/dclaude/.claude.json`) and have the entrypoint read from there; removes the nested-RO bind hazard |
| **P4: Windows symlinks** | No change planned; the one-time setup is acceptable. Considered for documentation only |
| **P5: Windows profile coupling** | Derive `ContainerAdministrator` dynamically (e.g., inspect `docker run --rm <image> cmd /c echo %USERPROFILE%`) or make it a configurable per-image setting |
| **P6: Sanitizer** | Invert to a denylist (strip known host-specific keys `projects`, `githubRepoPaths`; pass all unknowns through — fail-open); hoist the implementation to the PowerShell launcher so it runs once and the sanitized file is mounted in, eliminating per-platform duplication. Trade-off: fail-open risks leaking a future host-specific field into the container |

Rework is not yet scheduled. Scenario 3 (Linux host) support would require the launcher to gain
host-OS detection — currently a deliberate non-feature.
