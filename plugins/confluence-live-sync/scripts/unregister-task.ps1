<#
.SYNOPSIS
  Removes a scheduled task previously registered by register-task.ps1.

.DESCRIPTION
  Invoked by the /watch-stop command.
#>
param(
  [Parameter(Mandatory = $true)][string]$TaskName
)

$ErrorActionPreference = 'Stop'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $existing) {
  Write-Output "No scheduled task named '$TaskName' was found — nothing to remove."
  exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Output "Removed scheduled task '$TaskName'."
