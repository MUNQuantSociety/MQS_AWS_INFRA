<#
.SYNOPSIS
    Load .env into the current PowerShell session so terraform and the aws CLI
    can see it.

.DESCRIPTION
    Neither Terraform nor the aws CLI reads .env files -- both read the process
    environment. This script bridges the two.

    Environment variables set with $env: land in the process environment block,
    which is NOT scoped like a normal PowerShell variable, so they survive after
    this script exits. Dot-sourcing is not required. Opening a NEW terminal is a
    new process, so run this again there.

.PARAMETER Path
    Path to the env file. Defaults to .env in the repository root.

.EXAMPLE
    .\scripts\load-env.ps1
    aws sts get-caller-identity

.EXAMPLE
    .\scripts\load-env.ps1 -Path .env.livetrading
#>
[CmdletBinding()]
param(
    [string]$Path
)

$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "No env file at '$Path'. Copy the template first: cp .env.example .env"
    return
}

# Warn if the file is readable beyond this user. It holds live credentials, and
# this tree sits under OneDrive, so an over-permissive ACL means the file is
# also syncing somewhere with those same permissions.
$acl = Get-Acl -LiteralPath $Path
$broad = $acl.Access | Where-Object {
    $_.IdentityReference -match 'Everyone|BUILTIN\\Users|Authenticated Users' -and
    $_.AccessControlType -eq 'Allow'
}
if ($broad) {
    Write-Warning "$Path is readable beyond your user account. Restrict it: icacls `"$Path`" /inheritance:r /grant:r `"$env:USERNAME`:R`""
}

$loaded = 0
$skipped = 0

foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()

    # Comments and blanks.
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

    # KEY=VALUE. Anything else is malformed rather than meaningful -- say so
    # instead of silently dropping it, because a dropped credential surfaces
    # later as a confusing auth error.
    if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        Write-Warning "Skipping unparseable line: $trimmed"
        continue
    }

    $name = $Matches[1]
    $value = $Matches[2].Trim()

    # Strip one matching pair of surrounding quotes. A JSON value like
    # TF_VAR_db_secret_values={"a":"b"} has no outer quotes and is left alone.
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    # An empty value means "not filled in". Setting it would shadow a real
    # credential already in the environment, so skip it and count it.
    if ($value -eq '') {
        $skipped++
        continue
    }

    Set-Item -Path "env:$name" -Value $value
    $loaded++
}

Write-Host "Loaded $loaded variable(s) from $Path ($skipped left empty)."

if (-not $env:AWS_ACCESS_KEY_ID -and -not $env:AWS_PROFILE) {
    Write-Warning 'Neither AWS_ACCESS_KEY_ID nor AWS_PROFILE is set. terraform and aws will have no credentials.'
}
