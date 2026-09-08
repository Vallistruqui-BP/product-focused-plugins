<#
.SYNOPSIS
  Registers a Windows Scheduled Task that runs `claude -p "/sync-doc" --dangerously-skip-permissions`
  in a given project folder on a recurring interval, unattended.

.DESCRIPTION
  Invoked by the /watch-start command. Not meant to be run standalone without understanding that the
  resulting task runs Claude Code with ALL permission checks bypassed, indefinitely, until removed
  with unregister-task.ps1 (or /watch-stop).
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$TaskName,
  [Parameter(Mandatory = $true)][int]$IntervalMinutes,
  [string]$ClaudeExePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectPath)) {
  throw "ProjectPath does not exist: $ProjectPath"
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

if ([string]::IsNullOrWhiteSpace($ClaudeExePath)) {
  $cmd = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Could not resolve the 'claude' executable on PATH. Pass -ClaudeExePath explicitly."
  }
  $ClaudeExePath = $cmd.Source
}
if (-not (Test-Path -LiteralPath $ClaudeExePath)) {
  throw "ClaudeExePath does not exist: $ClaudeExePath"
}

if ($IntervalMinutes -lt 1) {
  throw "IntervalMinutes must be at least 1 (got $IntervalMinutes)."
}

$action = New-ScheduledTaskAction `
  -Execute $ClaudeExePath `
  -Argument '-p "/sync-doc" --dangerously-skip-permissions' `
  -WorkingDirectory $ProjectPath

$trigger = New-ScheduledTaskTrigger `
  -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
# [TimeSpan]::MaxValue serializes to a duration string ("P99999999DT23H59M59S") that exceeds
# what Task Scheduler's XML schema accepts. An empty string is the documented way to mean
# "repeat indefinitely" instead.
$trigger.Repetition.Duration = ''

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew

# S4U runs the task as this user (profile loaded, so `claude`'s stored auth is available) but in a
# non-interactive background session -- no console window, and it keeps working while locked/logged
# off, without needing a stored password. Without this, Register-ScheduledTask defaults to an
# interactive logon, which pops a visible console window every run and only fires while logged in.
$principal = New-ScheduledTaskPrincipal `
  -UserId "$env:USERDOMAIN\$env:USERNAME" `
  -LogonType S4U `
  -RunLevel Limited

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Principal $principal `
  -Description "confluence-live-sync watcher for $ProjectPath (runs claude -p /sync-doc --dangerously-skip-permissions every $IntervalMinutes min)" `
  -Force | Out-Null

# Register-ScheduledTask can emit a non-terminating error from its underlying CIM call without
# actually throwing, so verify the task exists before claiming success.
$registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $registered) {
  throw "Register-ScheduledTask did not report an error, but task '$TaskName' was not found afterward."
}

Write-Output "Registered scheduled task '$TaskName' (every $IntervalMinutes min) for $ProjectPath"
