@echo off
REM run_afmdw.bat - Launch AFMDW app inside a venv (Windows)
REM Edit VENV_PATH below if your virtual environment is located elsewhere.

REM ---------- Configuration ----------
REM By default this script looks for a "venv" folder next to this script.
REM You can override by setting VENV_PATH to the full path of your venv.
SETLOCAL
SET "SCRIPT_DIR=%~dp0"
SET "VENV_PATH=%SCRIPT_DIR%venv"

REM If the default venv path doesn't exist, try a common alternate
IF NOT EXIST "%VENV_PATH%\Scripts\activate.bat" (
    SET "VENV_PATH=C:\afmdw-venv"
)

REM ---------- Activate venv if available ----------
IF EXIST "%VENV_PATH%\Scripts\activate.bat" (
    echo Activating virtual environment: "%VENV_PATH%"
    call "%VENV_PATH%\Scripts\activate.bat"
) ELSE (
    echo Virtual environment not found at "%VENV_PATH%".
    echo You can either:
    echo  - Edit this file and set VENV_PATH to your venv location, or
    echo  - Create a venv at "%VENV_PATH%" and install dependencies.
    echo Attempting to run with system python in 5 seconds (press Ctrl-C to cancel)...
    timeout /t 5 /nobreak >nul
)

REM ---------- Ensure working directory is script dir ----------
CD /D "%SCRIPT_DIR%"

REM ---------- Ensure AFMDW_SHARED_DIR exists for this session ----------
IF "%AFMDW_SHARED_DIR%"=="" (
    REM default (session only) - change if you want persistent env var
    SET "AFMDW_SHARED_DIR=C:\ACCMVERSION1"
    echo AFMDW_SHARED_DIR not set; using default for this session: "%AFMDW_SHARED_DIR%"
)

REM ---------- Run the application ----------
REM Prefer pythonw (no console window) if available in the venv; otherwise use python
IF EXIST "%VENV_PATH%\Scripts\pythonw.exe" (
    "%VENV_PATH%\Scripts\pythonw.exe" "%SCRIPT_DIR%afmdw_app.py" %*
    SET "EXITCODE=%ERRORLEVEL%"
) ELSE (
    python "%SCRIPT_DIR%afmdw_app.py" %*
    SET "EXITCODE=%ERRORLEVEL%"
)

REM ---------- Deactivate venv (if activated) ----------
IF EXIST "%VENV_PATH%\Scripts\activate.bat" (
    IF DEFINED VIRTUAL_ENV (
        REM deactivate if activation script set VIRTUAL_ENV (common venv behavior)
        if exist "%VENV_PATH%\Scripts\deactivate.bat" (
            call "%VENV_PATH%\Scripts\deactivate.bat"
        )
    )
)

ENDLOCAL
EXIT /B %EXITCODE%