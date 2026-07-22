# PowerShell Toolbox

A personal collection of small PowerShell scripts, helper functions and administration snippets for everyday infrastructure work.

This repository is intended as a central place to store, clean up and document smaller scripts that were previously spread across different folders, notes, devices or project directories.

## Purpose

The goal of this toolbox is not to be a single large framework. It is a curated collection of practical PowerShell utilities for common administration, reporting, auditing and troubleshooting tasks.

Typical use cases include:

- Active Directory reporting
- Microsoft 365 administration helpers
- File server and NTFS permission analysis
- Printer and Universal Print related checks
- General Windows administration utilities
- Small reusable PowerShell functions

## Repository Structure

Recommended folder structure:

```text
powershell-toolbox/
├─ ActiveDirectory/
│  ├─ Reports/
│  ├─ Users/
│  ├─ Groups/
│  └─ Computers/
│
├─ Microsoft365/
│  ├─ EntraID/
│  ├─ ExchangeOnline/
│  ├─ Teams/
│  └─ Licensing/
│
├─ FileServices/
│  ├─ NTFS/
│  ├─ Shares/
│  └─ Reports/
│
├─ Printing/
│  ├─ UniversalPrint/
│  ├─ PrintServers/
│  └─ Reports/
│
├─ WindowsAdministration/
│  ├─ Services/
│  ├─ EventLogs/
│  └─ SystemInfo/
│
├─ .gitignore
└─ README.md
```

The structure can grow over time. Small scripts should first be placed in the most fitting category. If a topic becomes large enough, it can later be moved into its own dedicated repository.

## Naming Convention

Use clear and descriptive script names.

Recommended format:

```text
Verb-Noun-Context.ps1
```

Examples:

```text
Get-ADInactiveUsers.ps1
Get-ADGroupMembershipReport.ps1
Export-NTFSPermissions.ps1
Get-M365LicenseAssignment.ps1
```

Avoid unclear names such as:

```text
script.ps1
test_old.ps1
final_v2.ps1
usercheck.ps1
```

## Script Header Standard

Each script should start with a short documentation header.

```powershell
<#
.SYNOPSIS
Short description of what the script does.

.DESCRIPTION
Longer explanation of the purpose, scope and expected result.

.PARAMETER ExampleParameter
Description of the parameter.

.EXAMPLE
.\Get-ExampleReport.ps1 -OutputPath .\report.csv

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Created: YYYY-MM-DD
Last Updated: YYYY-MM-DD
#>
```

## Documentation Standard

Each larger script should include at least:

- Purpose
- Requirements
- Parameters
- Example usage
- Expected output
- Known limitations
- Required permissions

For scripts that create reports, include an example output file or a short output description.

Example:

```text
Output:
CSV file containing user principal name, display name, enabled state, last logon information and group membership summary.
```

## Security and Privacy Guidelines

This repository should not contain sensitive company information.

Do not commit:

- Passwords
- API secrets
- Access tokens
- Private keys
- Internal server names
- Customer data
- Personal user data exports
- Production configuration files
- Company-specific credentials
- Non-public infrastructure details

Use placeholders instead:

```powershell
$TenantId = "<tenant-id>"
$ServerName = "<server-name>"
$GroupName = "<group-name>"
```

## Recommended .gitignore

```gitignore
# PowerShell temporary files
*.log
*.tmp
*.bak
*.old

# Exported reports
*.csv
*.xlsx
*.json
*.xml

# Secrets and local configuration
*.secret.ps1
*.local.ps1
.env
secrets.json
config.local.json

# VS Code
.vscode/

# OS files
.DS_Store
Thumbs.db
```

## Quality Checklist Before Committing a Script

Before adding a script to this repository, check:

- [ ] Script has a clear name
- [ ] Script has a documentation header
- [ ] No secrets or internal data are included
- [ ] Parameters are used instead of hardcoded values where possible
- [ ] Output path is configurable
- [ ] Error handling is included
- [ ] Example usage is documented
- [ ] Script was tested in a safe environment
- [ ] README or documentation was updated if needed

## Long-Term Goal

The long-term goal is to turn this repository into a clean, reusable and well-documented toolbox for recurring infrastructure administration tasks.

Smaller scripts can remain in this repository. Larger or more specialized tools can later be promoted into dedicated repositories, for example:

```text
ad-governance-tools
universal-print-tools
ntfs-permission-audit
intune-automation
```

## Disclaimer

This repository contains personal scripts and examples. Scripts should be reviewed and tested before use in any production environment.

The content is provided as-is and may need to be adapted to specific environments, permissions and operational standards.

## Author

**Nico Bottoni**  
Senior ICT System Administrator  
Focus areas: Microsoft 365, Active Directory, Identity Governance, Enterprise Automation, File Services and Print Infrastructure.
