# Changelog

## [1.07] - 25.09.2026

### Changed
- Added per-repository discovery diagnostics.
- Discovery now prints the number of public repositories returned by GitHub, selected branch logic, and the exact HTTP/status/error for each attempted `upgrade.cmd`.
- This diagnostic release does not change the repository-processing architecture.


## [1.06] - 25.09.2026

### Changed
- Added explicit discovery diagnostics before repository processing.
- The runner now prints the number of managed repositories and each detected repository/branch pair.
- A zero-result discovery is highlighted as an error condition while preserving the full diagnostic output.


## [1.05] - 25.09.2026

### Changed
- Temporarily disabled the console clear immediately before the final summary table so diagnostic output remains visible.

### Fixed
- Fixed managed-repository discovery returning an empty set on Windows PowerShell 5.1.
- Missing `devel` branches now reliably fall back to each repository's GitHub default branch.
- Repository opt-in is verified by a real GET of the authoritative raw `upgrade.cmd`; a missing file excludes only that repository and does not abort discovery.
- Kept the 1.04 temporary PowerShell runner architecture unchanged.


## [1.04] - 25.09.2026

### Changed
- Replaced the large batch implementation with the documented tiny-launcher / authoritative-PowerShell-runner architecture.
- `global-upgrade.cmd` now fetches `origin/main`, extracts the current `global-upgrade.ps1` to a unique temporary file, and executes that immutable temporary runner.
- Repository synchronization can no longer replace the code currently executing.
- Repository processing and summary generation now run in PowerShell, removing CMD block-expansion and pseudo-tab parsing hazards.
- Preserved process-scoped exact Git `safe.directory` support for mapped/network repositories.

### Fixed
- Removed the unsafe self-update restart path that could lose the repository path after `git reset --hard`.
- Removed the old launcher-to-launcher `CALL` self-replacement design.


## [1.03] - 25.09.2026

### Fixed
- Replaced unreliable raw-content HEAD probing during repository discovery with the GitHub Contents API.
- A missing `devel` branch or `upgrade.cmd` is treated as the expected opt-out condition; other GitHub API errors are no longer silently swallowed.
- Discovery failures now print the actual PowerShell/GitHub error message for diagnostics.


## [1.02] - 25.09.2026

### Fixed
- Self-update handoff no longer uses `START`, so GlobalUpgrade remains in the original console window.
- The temporary launcher is invoked synchronously with `CALL`; all mutable repository operations remain outside the repository copy of the running script.
- The original launcher only receives the final exit code, removes its temporary launcher, and exits.


All notable changes to this project are documented in this file.

## [1.01] - 25.09.2026

### Changed
- Removed the GitHub CLI (`gh`) dependency.
- Public repository discovery now uses the GitHub REST API through standard Windows PowerShell.
- The console is cleared immediately when GlobalUpgrade starts.
- Reworked GlobalUpgrade startup around the proven self-update protocol documented in FolderHeatMap `UPGRADE.md`.
- The repository launcher now hands execution to a unique temporary copy before any Git synchronization can replace the running script.
- Added phase-zero self-update against `origin/main`.
- Added protection against silently overwriting tracked or staged local GlobalUpgrade changes.
- Added process-scoped exact Git `safe.directory` handling for local/mapped/network repository locations.
- Project `upgrade.cmd` downloads are normalized to CRLF before execution.
- Final process exit code is non-zero when one or more managed project upgrades fail.

### Removed
- GitHub CLI authentication requirement.

## [1.00] - 25.09.2026

### Added
- Initial GlobalUpgrade implementation.
- Automatic discovery of repositories from the Suenee GitHub account.
- Automatic preference for the `devel` branch when present.
- Opt-in repository management based on the presence of `upgrade.cmd`.
- Automatic refresh of each project's `upgrade.cmd` before execution.
- Support for missing and incomplete local repositories.
- Relative repository-root discovery based on the GlobalUpgrade directory.
- Support for installations on different local or mapped network drive letters.
- Failure isolation so one broken repository does not stop the remaining upgrades.
- Final color-coded summary table with repository, old version, current version, status, and result.
