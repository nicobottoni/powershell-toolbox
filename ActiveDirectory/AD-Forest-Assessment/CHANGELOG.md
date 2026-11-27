# Changelog

All notable changes to the AD Forest Assessment project are documented in this file.

The project uses semantic versioning for portfolio releases.

## [1.0.0] - 2026-11-27

### Added

- Modular PowerShell architecture with dedicated modules for:
  - Core functionality
  - Forest collection
  - Domain collection
  - Domain controller collection
  - User assessment
  - Computer assessment
  - Group assessment
  - Trust assessment
  - Security analysis
  - HTML reporting
- Timestamped assessment output directories.
- Central UTF-8 logging with `INFO`, `WARNING`, and `ERROR` levels.
- Central CSV export helper.
- Forest inventory including functional level, root domain, global catalogs, Schema Master, and Domain Naming Master.
- Domain inventory including NetBIOS name, functional level, distinguished name, PDC Emulator, RID Master, and Infrastructure Master.
- Domain controller inventory including site, IPv4 address, operating system, operating system version, Global Catalog status, and RODC status.
- User account health collection including:
  - Enabled/disabled status
  - Last logon date
  - Password last set
  - Password never expires
  - Password not required
  - Locked-out state
  - Never logged on
  - Configurable inactivity state
- Interdomain trust account detection using the `INTERDOMAIN_TRUST_ACCOUNT` `userAccountControl` flag.
- Computer account health collection including:
  - Enabled/disabled status
  - Operating system and version
  - Last logon date
  - Password last set
  - Never logged on
  - Configurable inactivity state
- Group health collection including:
  - Category and scope
  - Member count
  - Direct nested-group count
  - Empty-group detection
  - Description presence
  - Membership-query success state
- Trust collection including direction, type, forest transitivity, intra-forest state, selective authentication, and SID-filtering properties.
- Language-independent privileged-group discovery using well-known SIDs/RIDs.
- Direct and indirect privileged user membership classification.
- Security finding engine with structured severity, category, object, details, and recommendation fields.
- Security checks for privileged accounts, normal user accounts, and computer accounts.
- Suppression of normal user-security findings for interdomain trust accounts.
- Assessment configuration file with validated thresholds:
  - `InactiveUserDays`
  - `InactiveComputerDays`
  - `NewComputerGraceDays`
- Configuration validation for required keys, integer data types, and supported ranges.
- Assessment status model:
  - `Completed`
  - `CompletedWithWarnings`
  - `Failed`
- Controlled failure handling for missing/invalid configuration and fundamental forest collection failures.
- Query warnings for groups whose membership could not be fully enumerated.
- Assessment metadata including:
  - Tool version
  - Assessment host
  - PowerShell version
  - Start time
  - Completion time
  - Duration
- Self-contained offline HTML report with:
  - Assessment Status
  - Assessment Information
  - Executive Summary
  - Environment Overview
  - Security Findings
  - User Account Health
  - Computer Account Health
  - Group Health
  - Privileged Access
  - Trust Details
- Interactive HTML tables with:
  - Search
  - 10 / 25 / 50 / 100 rows per page
  - Pagination
  - Filtered CSV download
  - Correct header handling across pages
  - Automatic control hiding when no result table exists

### Changed

- Replaced legacy/manual CSV construction with PowerShell objects and `Export-Csv`.
- Replaced hardcoded inactivity naming (`InactiveOver90Days`) with configuration-independent `IsInactive` properties.
- Replaced localized privileged group-name matching with SID/RID-based resolution.
- Separated collection, assessment, and reporting responsibilities across modules.
- Centralized inactivity thresholds in `AssessmentConfig.psd1`.
- Updated HTML inactivity labels to use the configured user and computer thresholds.
- Hardened output directory creation, logging, and CSV export with terminating error handling.
- Changed group membership failures from implicit zero results to explicit unknown/query-error states.

### Fixed

- False-positive Critical findings for Active Directory interdomain trust accounts such as trusted-domain accounts ending in `$`.
- Empty collection handling when no privileged accounts, trusts, findings, or other optional result sets are present.
- HTML report generation when optional result collections are empty.
- Group membership enumeration errors causing noisy unhandled PowerShell errors.
- Interactive-table header being counted as a paginated data row.
- Missing table headers on pagination pages after the first page.
- Interactive table controls remaining visible when no table/data exists.
- Duplicate privileged-account risk interpretation caused by accounts appearing in multiple privileged groups.

### Notes

- Version 1.0.0 represents the first portfolio-ready release of the rewritten AD Forest Assessment framework.
- Production assessment output contains potentially sensitive directory information and should not be committed to a public repository.
- Automated Pester tests are not included in this release; validation was performed through iterative lab and live-environment testing during development.
