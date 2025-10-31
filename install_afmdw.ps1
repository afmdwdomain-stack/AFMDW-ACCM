<#
install_afmdw.ps1

Combined installer for AFMDW (Windows PowerShell).

What this script does:
- Creates the install folder (default C:\ACCMVERSION1).
- Creates a Python virtual environment (venv) inside the install folder (default: <InstallDir>\venv).
- Upgrades pip/setuptools/wheel in the venv and installs the recommended Python packages from an embedded requirements.txt.
- Writes a run_afmdw.bat launcher to the install folder (configured to use the venv created).
- Writes a small helper to create a Startup shortcut and registers that shortcut in the current user's Startup folder.
- Optionally re-runs installation if the venv already exists (use -Reinstall).

Usage (from an elevated or non-elevated PowerShell running as the user who will run the app):
  powershell -ExecutionPolicy Bypass -File .\install_afmdw.ps1 -InstallDir "C:\ACCMVERSION1"

Parameters:
  -InstallDir <string>   Path to install files (default: C:\ACCMVERSION1)
  -VenvRelative          If set, create venv as a subfolder "venv" under InstallDir (default: $true)
  -Reinstall             If set, force reinstall of requirements into an existing venv
  -SkipShortcut          If set, do not create the Startup shortcut
  -Quiet                 If set, reduce output
#>

param(
    [string]$InstallDir = "C:\ACCMVERSION1",
    [switch]$VenvRelative = $true,
    [switch]$Reinstall = $false,
    [switch]$SkipShortcut = $false,
    [switch]$Quiet = $false
)

function Write-Log {
    param($msg, $level = "INFO")
    if (-not $Quiet) { Write-Host "[$level] $msg" }
}

# Resolve paths
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
if ($VenvRelative) {
    $VenvPath = Join-Path -Path $InstallDir -ChildPath "venv"
} else {
    # fallback default
    $VenvPath = "C:\afmdw-venv"
}

# Requirements text (embedded)
$requirements = @"
filelock
passlib[bcrypt]
cryptography
keyring
reportlab
openpyxl
pillow
tkcalendar
"@.Trim()

# run_afmdw.bat contents (adjusted to use the venv created)
$runBat = @"
@echo off
REM run_afmdw.bat - Launch AFMDW app inside the venv created by installer

SETLOCAL
SET "SCRIPT_DIR=%~dp0"
REM Virtual environment path (installed by installer)
SET "VENV_PATH=%SCRIPT_DIR%venv"

REM If installed venv in a different location, adjust VENV_PATH above.
IF NOT EXIST "%VENV_PATH%\Scripts\activate.bat" (
    SET "VENV_PATH=C:\afmdw-venv"
)

IF EXIST "%VENV_PATH%\Scripts\activate.bat" (
    echo Activating virtual environment: "%VENV_PATH%"
    call "%VENV_PATH%\Scripts\activate.bat"
) ELSE (
    echo WARNING: Virtual environment not found at "%VENV_PATH%".
    echo Running with system python - ensure dependencies are installed.
    timeout /t 3 /nobreak >nul
)

CD /D "%SCRIPT_DIR%"

IF "%AFMDW_SHARED_DIR%"=="" (
    SET "AFMDW_SHARED_DIR=C:\ACCMVERSION1"
    echo AFMDW_SHARED_DIR not set; using default for this session: "%AFMDW_SHARED_DIR%"
)

IF EXIST "%VENV_PATH%\Scripts\pythonw.exe" (
    "%VENV_PATH%\Scripts\pythonw.exe" "%SCRIPT_DIR%afmdw_app.py" %*
) ELSE (
    python "%SCRIPT_DIR%afmdw_app.py" %*
)

ENDLOCAL
EXIT /B %ERRORLEVEL%
"@.Trim()

# Startup shortcut creation function (COM)
function New-StartupShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutName,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [string]$Arguments = "",
        [string]$IconLocation = ""
    )
    $shell = New-Object -ComObject WScript.Shell
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path -Path $startupFolder -ChildPath ("{0}.lnk" -f $ShortcutName)
    $sc = $shell.CreateShortcut($shortcutPath)
    $sc.TargetPath = $TargetPath
    if ($Arguments -ne "") { $sc.Arguments = $Arguments }
    $sc.WorkingDirectory = Split-Path -Parent $TargetPath
    if ($IconLocation -ne "") { $sc.IconLocation = $IconLocation }
    $sc.Save()
    return $shortcutPath
}

# Ensure install dir exists
try {
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        Write-Log "Created install directory: $InstallDir"
    } else {
        Write-Log "Install directory exists: $InstallDir"
    }
} catch {
    Write-Error "Failed to create or access install directory '$InstallDir': $_"
    exit 1
}

# Write requirements.txt
$reqFile = Join-Path $InstallDir "requirements.txt"
try {
    $requirements | Out-File -FilePath $reqFile -Encoding utf8 -Force
    Write-Log "Wrote requirements.txt to $reqFile"
} catch {
    Write-Error "Failed to write requirements file: $_"
    exit 1
}

# Create venv if missing
if (-not (Test-Path -LiteralPath (Join-Path $VenvPath "Scripts\activate.bat"))) {
    Write-Log "Creating virtual environment at $VenvPath ..."
    try {
        & python -m venv $VenvPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "python -m venv failed (exit code $LASTEXITCODE). Ensure Python 3.8+ is on PATH."
            exit 1
        }
        Write-Log "Virtual environment created."
    } catch {
        Write-Error "Failed to create virtual environment: $_"
        exit 1
    }
} else {
    Write-Log "Virtual environment already exists at $VenvPath"
    if (-not $Reinstall) {
        Write-Log "Skipping venv recreation (use -Reinstall to force)."
    }
}

# Use venv python to upgrade pip & install requirements
$venvPython = Join-Path $VenvPath "Scripts\python.exe"
$venvPip = Join-Path $VenvPath "Scripts\pip.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Error "Cannot find python in venv ($venvPython). Aborting."
    exit 1
}

Write-Log "Upgrading pip, setuptools, wheel ..."
& $venvPython -m pip install --upgrade pip setuptools wheel 2>&1 | ForEach-Object { if (-not $Quiet) { Write-Host $_ } }
if ($LASTEXITCODE -ne 0) {
    Write-Log "Warning: pip upgrade returned non-zero exit code $LASTEXITCODE" "WARN"
}

# Install packages
$installArgs = @("-m","pip","install","-r", $reqFile)
if ($Reinstall) {
    Write-Log "Reinstall mode: forcing upgrade of installed packages"
    $installArgs += "--upgrade"
}
Write-Log "Installing required Python packages into venv..."
try {
    & $venvPython @installArgs 2>&1 | ForEach-Object { if (-not $Quiet) { Write-Host $_ } }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "pip install encountered errors (exit code $LASTEXITCODE). Continuing, but cryptography or other packages may have failed to build." "WARN"
        Write-Log "If you see cryptography wheel build errors on Windows, try running: `pip install --upgrade pip setuptools wheel` then `pip install cryptography --only-binary :all:`" "WARN"
    } else {
        Write-Log "Python packages installed successfully."
    }
} catch {
    Write-Log "pip install threw an exception: $_" "ERROR"
}

# Write run_afmdw.bat
$runBatPath = Join-Path $InstallDir "run_afmdw.bat"
try {
    $runBat | Out-File -FilePath $runBatPath -Encoding ascii -Force
    Write-Log "Wrote launcher: $runBatPath"
} catch {
    Write-Error "Failed to write run_afmdw.bat: $_"; exit 1
}

# Ensure AFMDW_SHARED_DIR environment variable is set for current user (persisted)
try {
    $currentAFMDW = [Environment]::GetEnvironmentVariable("AFMDW_SHARED_DIR", "User")
    if (-not $currentAFMDW -or ($currentAFMDW -ne $InstallDir)) {
        Write-Log "Setting AFMDW_SHARED_DIR (user-level) to $InstallDir"
        setx AFMDW_SHARED_DIR $InstallDir | Out-Null
        Write-Log "AFMDW_SHARED_DIR set persistently for current user. You may need to log off/in for other processes to see it."
    } else {
        Write-Log "AFMDW_SHARED_DIR already set to $currentAFMDW (user-level)"
    }
} catch {
    Write-Log "Failed to set AFMDW_SHARED_DIR persistently: $_" "WARN"
}

# Create Startup shortcut unless skipped
if (-not $SkipShortcut) {
    try {
        $target = $runBatPath
        $link = New-StartupShortcut -ShortcutName "AFMDW App" -TargetPath $target
        Write-Log "Startup shortcut created at: $link"
    } catch {
        Write-Log "Failed to create Startup shortcut: $_" "WARN"
    }
} else {
    Write-Log "Skipping creation of Startup shortcut (SkipShortcut specified)."
}

# Final notes & verification
Write-Log "Installation complete."
Write-Log "Next steps:"
Write-Log " - Place afmdw_app.py (and any other provided files like file_locking.py/auth_storage.py if you use them externally) into $InstallDir."
Write-Log " - Activate the venv to run manually: `& `"$VenvPath\Scripts\Activate.ps1`"` (PowerShell) or run the launcher: `"$runBatPath"`."
Write-Log " - If you installed cryptography and it failed to build, re-run the pip command suggested in the warnings."

# Exit 0
exit 0