```markdown
# AFMDW Package - Quick README

Contents:
- afmdw_app.py            - main application (not included in this list; place it in the same folder)
- file_locking.py         - atomic JSON persistence + optional file locking
- auth_storage.py         - secure user and SMTP secret helpers
- run_afmdw.bat           - Windows launcher that activates the venv and runs afmdw_app.py
- install_afmdw.ps1       - installer: creates venv, installs requirements, writes run_afmdw.bat, sets AFMDW_SHARED_DIR, creates Startup shortcut
- create_startup_shortcut.ps1 - helper to create a Startup .lnk
- create_schtask.ps1      - helper to register a scheduled task (optional)
- requirements.txt        - pip requirements used by installer

Quick install (single machine)
1. Copy all files into a folder on the machine that will host the shared storage (e.g. C:\ACCMVERSION1).
2. Place afmdw_app.py in the same folder.
3. Open PowerShell as the user who will run the app and run:
   powershell -ExecutionPolicy Bypass -File .\install_afmdw.ps1 -InstallDir "C:\ACCMVERSION1"
   This will create a venv under C:\ACCMVERSION1\venv, install dependencies, set AFMDW_SHARED_DIR for the user, and create a Startup shortcut.
4. After install, run run_afmdw.bat (or sign out/in to trigger the Startup shortcut).

Create distributable ZIP
From the folder containing the files:
```powershell
Compress-Archive -Path afmdw_app.py,file_locking.py,auth_storage.py,run_afmdw.bat,install_afmdw.ps1,create_startup_shortcut.ps1,create_schtask.ps1,requirements.txt,README.md -DestinationPath AFMDW_Package.zip -Force
```

Publish release (gh CLI)
```bash
gh auth login
gh release create v1.0.0 AFMDW_Package.zip --repo afmdwdomain-stack/AFMDW-ACCM --title "AFMDW v1.0.0" --notes "Initial packaged release containing AFMDW application, installer, and helper scripts."
```

Notes & troubleshooting
- If cryptography fails to install on Windows, run:
  python -m pip install --upgrade pip setuptools wheel
  python -m pip install cryptography --only-binary :all:
- If you don't have filelock installed, the app will still write JSON atomically but will not serialize concurrent access across processes.
- For best security: set AFMDW_MASTER_PASSPHRASE environment variable (same on all clients) to enable encrypted SMTP credential storage; otherwise the installer will use OS keyring where available.
- Back up the Bookings folder periodically. The installer creates timestamped backups on each save but off-site backups are recommended.

Support
- If you want, I can create the GitHub release for you (I provided gh commands above), or produce an MSI/installer that bundles the Python runtime. Contact me with which option you prefer.
```