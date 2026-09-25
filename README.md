# GlobalUpgrade

GlobalUpgrade is a centralized Windows updater for repositories owned by **Suenee**.

It discovers public repositories directly from GitHub and manages only projects that explicitly opt in by providing an `upgrade.cmd` file in their authoritative branch.

## Version

Current version: **1.01**

## Requirements

- Windows 10/11
- Git
- Windows PowerShell

No GitHub CLI, GitHub authentication, or other helper installation is required for public repositories.

## Self-update

Self-update is phase zero and follows the shared Wipe Codes upgrade protocol.

The repository copy of `global-upgrade.cmd` immediately transfers execution to a unique temporary launcher. The temporary launcher fetches `origin/main`, compares local and remote HEAD, and synchronizes GlobalUpgrade before normal repository processing starts.

The repository launcher never continues reading after an operation that can replace it. This avoids the known CMD self-replacement failure mode.

Tracked or staged local changes are never silently destroyed. Self-update stops with a clear error instead.

GlobalUpgrade deliberately does **not** contain `upgrade.cmd`. It therefore remains naturally excluded from the normal managed-project discovery process and cannot recursively invoke itself.

## Managed repositories

- Repository discovery comes directly from the public GitHub API.
- `devel` is authoritative whenever that branch exists.
- Otherwise the repository default branch is authoritative.
- A repository without `upgrade.cmd` in the selected branch is ignored completely.
- Before execution, the authoritative project `upgrade.cmd` is downloaded and normalized to Windows CRLF.
- Missing/incomplete local repositories are passed to the project's own updater for bootstrap.
- One project failure never prevents processing of the remaining projects.
- The project updater's exit code is authoritative.

## Location independence

The repository root is derived from the physical location of GlobalUpgrade. No drive letter is hard-coded.

Mapped network drives are supported. Repository access uses `pushd`, and Git `safe.directory` is scoped to the current process and exact repository path.

## Usage

Run:

```cmd
global-upgrade.cmd
```

The console is cleared immediately at startup. After self-update and project processing, GlobalUpgrade clears the console again and displays the final color-coded summary.

## Result table

```text
GLOBAL UPGRADE 1.01
==========================================================================================
Repository                         Old          Version      Status       Result
------------------------------------------------------------------------------------------
FolderHeatMap                                   1.53         CURRENT      OK
VoicePrompter                      0.18.11      0.18.12      UPDATED      OK
VirtualMonitorsUniverse                         1.08         INSTALLED    OK
ExampleProject                     0.03         0.03         UPDATE       FAIL
------------------------------------------------------------------------------------------

OK: 3    FAIL: 1
```

The `Old` column is populated only when the detected project version actually changes.

GlobalUpgrade does not keep a persistent global log. Detailed upgrade logging remains the responsibility of each managed project's `upgrade.cmd`.
