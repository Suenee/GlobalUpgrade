# Changelog

All notable changes to this project are documented in this file.

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
- Version detection from `VERSION`, `package.json`, and common manifest/source files.
