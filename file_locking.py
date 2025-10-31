# file_locking.py
# Network-safe file locking and atomic JSON persistence helpers.
# Requires: pip install filelock
#
# Provides:
#   load_json_locked(path, default=None, timeout=...)
#   save_json_locked(path, obj, make_backup=True, timeout=...)
#   ensure_shared_paths(shared_dir) -> dict of paths
#
# Behavior:
# - When "filelock" is installed this module will use FileLock to serialize access.
# - Writes are atomic (tmp file + os.replace) and create timestamped backups when requested.
# - Designed for use on a shared network folder (AFMDW use-case).

import os
import json
import shutil
import logging
from datetime import datetime

try:
    from filelock import FileLock, Timeout
    FILELOCK_AVAILABLE = True
except Exception:
    FileLock = None
    Timeout = Exception
    FILELOCK_AVAILABLE = False

logger = logging.getLogger("file_locking")
LOCK_TIMEOUT_SECONDS = int(os.environ.get("AFMDW_LOCK_TIMEOUT", "20"))


def _lock_path(path: str) -> str:
    return path + ".lock"


def load_json_locked(path: str, default=None, timeout: int = LOCK_TIMEOUT_SECONDS):
    """
    Load JSON from `path` under an exclusive lock (when filelock is available).
    Returns `default` if the file is missing or unreadable.
    Raises RuntimeError on lock timeout.
    """
    if FILELOCK_AVAILABLE:
        lock = FileLock(_lock_path(path))
        try:
            with lock.acquire(timeout=timeout):
                if not os.path.exists(path):
                    return default
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        return json.load(f)
                except Exception:
                    logger.exception("Failed to parse JSON %s", path)
                    return default
        except Timeout:
            raise RuntimeError(f"Timed out acquiring lock for reading {path!s}")
    else:
        # best-effort fallback (no inter-process lock)
        if not os.path.exists(path):
            return default
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            logger.exception("Failed to read/parse JSON %s (no lock available)", path)
            return default


def save_json_locked(path: str, obj, make_backup: bool = True, timeout: int = LOCK_TIMEOUT_SECONDS):
    """
    Save JSON to `path` atomically while holding a file lock (if available).
    Creates a timestamped backup when make_backup=True and the destination exists.
    Raises RuntimeError on lock timeout.
    """
    if FILELOCK_AVAILABLE:
        lock = FileLock(_lock_path(path))
        try:
            with lock.acquire(timeout=timeout):
                os.makedirs(os.path.dirname(path), exist_ok=True)

                if make_backup and os.path.exists(path):
                    try:
                        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
                        bak = f"{path}.{ts}.bak"
                        shutil.copy2(path, bak)
                    except Exception:
                        logger.exception("Failed to create backup for %s", path)

                tmp = path + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(obj, f, indent=2, default=str)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp, path)
        except Timeout:
            raise RuntimeError(f"Timed out acquiring lock for writing {path!s}")
    else:
        # fallback: atomic write without inter-process locking
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if make_backup and os.path.exists(path):
            try:
                ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
                bak = f"{path}.{ts}.bak"
                shutil.copy2(path, bak)
            except Exception:
                logger.exception("Failed to create backup for %s", path)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, default=str)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)


def ensure_shared_paths(shared_dir: str):
    """
    Create and return structured paths for a shared root.
    Ensures the following subfolders exist:
      - <shared_dir>/Bookings
      - <shared_dir>/Monthly_reports
      - <shared_dir>/certificates

    Returns a dict with keys:
      shared_root, bookings_dir, bookings_file, bookedout_file, reports_dir, certs_dir
    """
    if not shared_dir:
        raise ValueError("shared_dir must be a non-empty path")
    shared_dir = os.path.abspath(shared_dir)
    bookings_dir = os.path.join(shared_dir, "Bookings")
    reports_dir = os.path.join(shared_dir, "Monthly_reports")
    certs_dir = os.path.join(shared_dir, "certificates")

    for d in (shared_dir, bookings_dir, reports_dir, certs_dir):
        os.makedirs(d, exist_ok=True)

    return {
        "shared_root": shared_dir,
        "bookings_dir": bookings_dir,
        "bookings_file": os.path.join(bookings_dir, "bookings.json"),
        "bookedout_file": os.path.join(bookings_dir, "booked_out_records.json"),
        "reports_dir": reports_dir,
        "certs_dir": certs_dir,
    }