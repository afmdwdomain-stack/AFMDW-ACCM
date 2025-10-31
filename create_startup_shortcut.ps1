<#
create_startup_shortcut.ps1
Creates a Windows Startup shortcut for the current user that launches run_afmdw.bat.

Usage (run as the user who should auto-start the app):
  powershell -ExecutionPolicy Bypass -File .\create_startup_shortcut.ps1 -Name "AFMDW App" -TargetPath "C:\path\to\run_afmdw.bat"
#>

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [string]$Arguments = "",
    [string]$IconLocation = ""
)

# Resolve paths
$TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path -Path $StartupFolder -ChildPath ($Name + ".lnk")

# Create WScript.Shell COM object and shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath  = $TargetPath
$Shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
if ($Arguments -ne "") { $Shortcut.Arguments = $Arguments }
if ($IconLocation -ne "") { $Shortcut.IconLocation = $IconLocation }
$Shortcut.Save()

Write-Host "Created startup shortcut for current user:"
Write-Host "  $ShortcutPath"