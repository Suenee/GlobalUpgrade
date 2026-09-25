# GlobalUpgrade

GlobalUpgrade is a centralized Windows updater for repositories owned by **Suenee**.

It discovers repositories directly from GitHub and manages only projects that explicitly opt in by providing an `upgrade.cmd` file in their authoritative branch.

## Version

Current version: **1.00**

## Core rules

- Repository discovery comes from GitHub; there is no manually maintained project list.
- If a repository contains a `devel` branch, `devel` is authoritative.
- Otherwise, the repository's default branch is used.
- A repository without `upgrade.cmd` in the selected branch is ignored completely.
- Before a project updater is executed, the local `upgrade.cmd` is refreshed from GitHub.
- This protects against outdated, broken, missing, or incomplete local updaters.
- Existing repositories are checked against the selected upstream branch.
- Missing or incomplete repositories are handed to their own current `upgrade.cmd` for bootstrap/repair.
- Failure of one repository never stops processing of the remaining repositories.
- Each project remains responsible for its own detailed logging and upgrade logic.
- GlobalUpgrade itself does not contain `upgrade.cmd`, so it is naturally excluded by the same opt-in rule and cannot recursively invoke itself.

## Location independence

GlobalUpgrade determines the repository root from its own physical location.

Example:

```text
D:\WORK\GitHub\GlobalUpgrade\global-upgrade.cmd
                     ↓
D:\WORK\GitHub\
```

The same installation can therefore be moved to another drive letter, including mapped network drives such as `N:`, without changing the script.

## Requirements

- Windows 10/11
- Git
- GitHub CLI (`gh`)
- Authenticated GitHub CLI session
- PowerShell

Authenticate GitHub CLI once with:

```cmd
gh auth login
```

## Result table

At the end of every run the screen is cleared and a summary is displayed:

```text
GLOBAL UPGRADE 1.00
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

The `Old` column is populated only when the version changed during the run.

Successful rows are shown in green and failed rows in red.

## Status values

- `CURRENT` — repository was already current.
- `UPDATED` — existing repository was successfully updated.
- `INSTALLED` — missing/incomplete repository was successfully bootstrapped.
- `UPDATE` / `INSTALL` — attempted operation failed.
- `UPDATER` — refreshing `upgrade.cmd` failed.
- `CHECK` — the local repository could not be inspected.

## Logging

GlobalUpgrade intentionally does not maintain a permanent execution log. Each managed repository keeps its own upgrade log according to that project's logging rules.

## Repository layout

GlobalUpgrade is expected to live next to the repositories it manages:

```text
GitHub\
├── FolderHeatMap\
├── GlobalUpgrade\
│   └── global-upgrade.cmd
├── VoicePrompter\
└── ...
```
