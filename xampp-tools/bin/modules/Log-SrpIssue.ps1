# Name: Log SRP Issue
# Description: Manually log SRP issues to audit log
# Icon: 📝
# Cmd: log-srp-issue
# Order: 15
# Hidden: true

<#
.SYNOPSIS
    Log SRP Issue - Manually document SRP errors for troubleshooting

.DESCRIPTION
    Logs an SRP issue to the daily audit log with:
    - Issue description
    - Fix applied
    - Result (Success/Fail)
    
    Used for tracking SRP configuration problems and their resolutions.
#>

# Get paths
$moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $moduleRoot "bin\Common.ps1")

$script:BackupDir = Join-Path $moduleRoot "backups"

# ============================================================
# MAIN
# ============================================================

Show-Header

Write-Host ""
Write-Host "  📝 Log SRP Issue" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  This tool logs SRP issues to the daily audit log for troubleshooting" -ForegroundColor Gray
Write-Host ""

# Get issue description
Write-Host "  Issue Description:" -ForegroundColor White
Write-Host "  (What SRP error occurred?)" -ForegroundColor Gray
$issue = Read-Host "  > "

if ([string]::IsNullOrWhiteSpace($issue)) {
    Write-Warning2 "Issue description cannot be empty"
    exit
}

Write-Host ""

# Get applied fix
Write-Host "  Fix Applied:" -ForegroundColor White
Write-Host "  (What did you do to fix it?)" -ForegroundColor Gray
$apply = Read-Host "  > "

if ([string]::IsNullOrWhiteSpace($apply)) {
    Write-Warning2 "Fix description cannot be empty"
    exit
}

Write-Host ""

# Get result
Write-Host "  Result:" -ForegroundColor White
$resultResponse = Read-Host "  (Success or Fail?) [S/f]"
$result = if ($resultResponse -match '^[Ff]') { "Fail" } else { "Success" }

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Log to audit
$today = Get-Date -Format "yyyy-MM-dd"
$auditDir = Join-Path $script:BackupDir $today
$logPath = Write-AuditLog -Issue $issue -Apply $apply -Result $result -LogDir $auditDir

Write-Success "Issue logged to: backups/$today/srp-audit.log"

Write-Host ""
Write-Host "  Details:" -ForegroundColor DarkGray
Write-Host "    Issue:  $issue" -ForegroundColor Gray
Write-Host "    Apply:  $apply" -ForegroundColor Gray
Write-Host "    Result: $result" -ForegroundColor Gray
Write-Host ""
