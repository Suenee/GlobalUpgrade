# Changelog

## [1.15] - 25.09.2026

### Fixed
- Recover failed-upgrade state from each project's existing `logs/upgrade.log`, so failures from runs before the GlobalUpgrade state marker existed are retried instead of reported as current.
- Detect application versions from nested project files when version metadata is not stored at the repository root.
- Nested `.csproj` discovery ignores common build and test directories and prefers repository-matching and shallower application projects.


## [1.14] - 25.09.2026

### Fixed
- Persist failed project-upgrade state in GlobalUpgrade.
- A repository whose last upgrade failed is retried on the next global run even when its local Git HEAD already matches the selected remote branch.
- The failure marker is removed only after the project updater succeeds and repository synchronization is verified.
- This prevents a failed build/test/deploy from being reported as `CURRENT / OK` on the next run.


## [1.13] - 25.09.2026

### Fixed
- Child updater execution now uses a waited child process with an explicit exit code.
- A project update is not accepted as successful unless the local repository HEAD matches the selected remote branch after the updater returns.
- Improved project version detection by reading `VERSION`, `package.json`, `Directory.Build.props`, or a root `.csproj` when available.


## [1.12] - 25.09.2026

### Fixed
- Existing repositories are no longer modified by GlobalUpgrade before their own updater starts.
- The authoritative remote `upgrade.cmd` is written only for fresh/bootstrap installations.
- Existing repositories keep ownership of their own updater self-update workflow, preventing GlobalUpgrade from creating tracked `upgrade.cmd` changes.
- Project launchers are invoked explicitly through `cmd.exe /d /c call upgrade.cmd`, and the child process exit code is captured immediately for the final result.


## [1.11] - 25.09.2026

### Changed
- Added blank lines between diagnostic sections and individual repository checks for easier console reading.
- Detailed discovery diagnostics remain enabled and the console is still not cleared before the final summary.


## [1.10] - 25.09.2026

### Changed
- Repositories with `CURRENT / OK` status are shown in yellow in the final summary.
- Successful updates remain green, successful fresh installations blue, and failures red.


## [1.09] - 25.09.2026

### Fixed
- Fixed authoritative `upgrade.cmd` downloads writing literal `\\r\\n` text instead of real Windows CRLF line endings.

### Changed
- Successful fresh installations are shown in blue in the final summary.
- Failed installations and failed updates remain red.
- Successful current/updated repositories remain green.
- Detailed discovery diagnostics remain enabled temporarily.


## [1.08] - 25.09.2026

### Fixed
- Fixed Windows PowerShell repository enumeration wrapping the GitHub response as a single nested `System.Object[]`.
- Normalized GitHub REST repository responses before discovery so each repository is processed individually.
- Kept detailed discovery diagnostics enabled temporarily.


## [1.08] - 25.09.2026

### Fixed
- Fixed Windows PowerShell repository enumeration wrapping the GitHub response as a single nested `System.Object[]`.
- Normalized GitHub REST repository responses before discovery so each repository is processed as an individual object.
- Kept detailed discovery diagnostics enabled temporarily.


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
