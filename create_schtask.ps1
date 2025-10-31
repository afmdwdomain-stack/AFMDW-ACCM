<#
create_schtask.ps1
Create a Scheduled Task that runs run_afmdw.bat at user logon.

Usage (may require elevation to register with highest privileges):
  PowerShell (elevated):
    .\create_schtask.ps1 -TaskName "AFMDW App" -ScriptPath "C:\path\to\run_afmdw.bat" -RunHighest $true

Notes:
- On Windows 7/10, creating a task for "Run only when user is logged on" doesn't require storing credentials.
- If you want the task to run highest privileges use -RunHighest $true (requires elevation).
#>

param(
    [Parameter(Mandatory=$true)][string]$TaskName,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [switch]$RunHighest,
    [switch]$Interactive  # when set, Task will run only when user is logged on (no credentials)
)

# Resolve script path
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path

# Build schtasks command
$action = "`"$ScriptPath`""
$sc = "ONLOGON"
$tn = $TaskName
$force = "/F"

if ($RunHighest) {
    $rl = "/RL HIGHEST"
} else {
    $rl = "/RL LIMITED"
}

# If Interactive (default), register for current user and no password prompt:
# schtasks /Create /TN "Name" /TR "path" /SC ONLOGON /RL LIMITED /F
$cmd = "schtasks /Create /TN `"$tn`" /TR `"$action`" /SC $sc $rl $force"

Write-Host "Creating scheduled task with command:"
Write-Host $cmd

$proc = Start-Process -FilePath schtasks -ArgumentList "/Create","/TN",$tn,"/TR",$action,"/SC",$sc,$rl,$force -NoNewWindow -Wait -PassThru

if ($proc.ExitCode -eq 0) {
    Write-Host "Scheduled task '$tn' created successfully."
    Write-Host "It will run at logon for the current user."
} else {
    Write-Host "schtasks exited with code $($proc.ExitCode). You may need to run this script elevated."
}