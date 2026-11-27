# AD Forest Assessment

A modular PowerShell framework for assessing the inventory, account health, privileged access, trust relationships, and selected security conditions of an on-premises Active Directory forest.

The project was rebuilt from the ground up as a portfolio project with a focus on maintainability, structured data collection, transparent findings, resilient execution, and an offline-capable HTML report.

## Features

### Active Directory inventory

- Forest information and functional level
- Domain information and FSMO role holders
- Domain controller inventory
- User account inventory and health indicators
- Computer account inventory and health indicators
- Group inventory, membership counts, nesting, and documentation status
- Domain and forest trust relationships
- Privileged account discovery using well-known SIDs/RIDs instead of localized group names
- Direct and indirect privileged group memberships

### Security assessment

The assessment generates structured findings with severity, category, affected object, details, and a recommendation.

Current checks include:

- Privileged accounts with non-expiring passwords
- Privileged accounts that do not require a password
- Privileged accounts that have never logged on
- Inactive privileged accounts
- Disabled accounts that retain privileged group membership
- Enabled non-privileged accounts with `PasswordNotRequired`
- Enabled non-privileged accounts with `PasswordNeverExpires`
- Enabled stale computer accounts
- Enabled computer accounts that have never logged on after the configured grace period

Interdomain trust accounts are identified through the `INTERDOMAIN_TRUST_ACCOUNT` flag in `userAccountControl` and excluded from normal user-security checks to avoid false-positive findings.

### Reporting

Each assessment run creates a timestamped output directory containing technical exports and a self-contained HTML report.

The HTML report includes:

- Assessment status and warnings
- Assessment metadata and runtime
- Executive Summary
- Environment Overview
- Security Finding Details
- User Account Health
- Computer Account Health
- Group Health
- Privileged Access Details
- Trust Details

Large detail tables support:

- Search/filtering
- 10 / 25 / 50 / 100 rows per page
- Pagination
- CSV download of the filtered result set
- Automatic removal of table controls when no result table exists

The report uses embedded HTML, CSS, and JavaScript and does not require an external CDN or internet connection.

## Project structure

```text
AD-Forest-Assessment/
|-- Config/
|   `-- AssessmentConfig.psd1
|-- Modules/
|   |-- ADA.Core.psm1
|   |-- ADA.Forest.psm1
|   |-- ADA.Domain.psm1
|   |-- ADA.DomainController.psm1
|   |-- ADA.User.psm1
|   |-- ADA.Computer.psm1
|   |-- ADA.Group.psm1
|   |-- ADA.Trust.psm1
|   |-- ADA.Security.psm1
|   `-- ADA.Reporting.psm1
|-- Output/
|-- Invoke-ADForestAssessment.ps1
|-- README.md
|-- CHANGELOG.md
`-- LICENSE
```

## Architecture

The framework separates collection, analysis, and reporting responsibilities.

```text
Active Directory
      |
      v
Collection Modules
      |
      v
PowerShell Objects
      |
      +------------------+
      |                  |
      v                  v
Security Analysis     CSV Export
      |
      v
Structured Findings
      |
      v
HTML Reporting
```

This separation allows security checks and reporting logic to evolve without embedding Active Directory queries throughout the project.

## Requirements

- Windows PowerShell 5.1 or a compatible PowerShell environment
- Active Directory PowerShell module (`ActiveDirectory`)
- Network connectivity to the target Active Directory environment
- Sufficient directory read permissions for the objects being assessed

Local administrator privileges are not required solely for normal Active Directory read operations.

## Configuration

Assessment thresholds are stored in:

```text
Config/AssessmentConfig.psd1
```

Default configuration:

```powershell
@{
    InactiveUserDays       = 90
    InactiveComputerDays   = 90
    NewComputerGraceDays   = 30
}
```

Supported ranges:

| Setting | Valid range | Default |
|---|---:|---:|
| `InactiveUserDays` | 1-365 days | 90 |
| `InactiveComputerDays` | 1-365 days | 90 |
| `NewComputerGraceDays` | 0-365 days | 30 |

The configuration is validated before the assessment starts. Missing settings, invalid data types, and values outside the supported ranges cause a controlled failure before Active Directory collection begins.

## Usage

From the project root:

```powershell
.\Invoke-ADForestAssessment.ps1
```

The script automatically:

1. Checks prerequisites.
2. Loads and validates the assessment configuration.
3. Creates a timestamped output directory.
4. Collects forest, domain, domain controller, user, computer, group, privileged-access, and trust data.
5. Evaluates configured security conditions.
6. Exports collected data and findings to CSV.
7. Generates the HTML assessment report.
8. Records the final assessment status and warnings.

## Output

Example:

```text
Output/
`-- AD-Assessment-20261127-090730/
    |-- AD-Forest-Assessment.html
    |-- Assessment.log
    |-- Forest.csv
    |-- Domains.csv
    |-- DomainControllers.csv
    |-- Users.csv
    |-- Computers.csv
    |-- Groups.csv
    |-- PrivilegedAccounts.csv
    |-- Findings.csv
    `-- Trusts.csv              # only when trusts are present
```

The output directory contains environment-specific and potentially sensitive Active Directory information. Real assessment output should therefore not be committed to a public portfolio repository.

A recommended `.gitignore` entry is:

```gitignore
Output/*
!Output/.gitkeep
```

## Assessment status

The framework distinguishes three execution states:

- `Completed` - the assessment completed without known collection warnings.
- `CompletedWithWarnings` - the assessment completed, but one or more non-fatal queries could not be completed.
- `Failed` - a fundamental prerequisite, configuration, or core collection step failed and the assessment was stopped.

For example, an individual group membership query failure is reported as a warning rather than silently interpreted as zero nested memberships.

## Finding severity

| Severity | Intended meaning |
|---|---|
| Critical | Configuration requiring immediate review because it materially weakens account security |
| High | Significant issue affecting privileged-access security |
| Medium | Security or hygiene condition requiring review but normally requiring operational context |
| Low | Lower-risk condition or residual privileged-access hygiene issue |

Findings are intended as assessment indicators, not automatic proof of compromise. Environment-specific context should always be considered before remediation.

## Privileged group detection

Built-in privileged groups are resolved through well-known SIDs/RIDs rather than English or localized display names. This avoids dependencies on domain language and supports environments where groups are named, for example, `Domain Admins` or `Domänen-Admins`.

The assessment currently evaluates direct and recursively resolved indirect user memberships and labels them as `Direct` or `Indirect`.

## Known limitations

- The assessment is read-only, but large environments can still generate significant LDAP query volume.
- `LastLogonDate` is based on the replicated `lastLogonTimestamp` representation and is appropriate for stale-account assessment, not exact last-logon forensics.
- Direct-versus-indirect privileged access is reported, but the complete nested membership path is not reconstructed.
- Some Active Directory groups can fail membership enumeration because of directory-side or object-specific conditions. These are reported through `MembershipQuerySuccessful` and the assessment warning status rather than treated as zero memberships.
- Security findings are deliberately limited to deterministic checks implemented by the framework and should not be treated as a replacement for a full Active Directory security product or manual security review.

## Security and portfolio usage

Before publishing screenshots or sample outputs:

- Use lab or synthetic data.
- Remove real usernames, server names, domain names, IP addresses, group structures, trust relationships, and findings.
- Do not commit production assessment output.
- Review repository history before making a previously private repository public.

## Version

Current portfolio release: **1.0.0**
