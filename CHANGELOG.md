# Changelog

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
