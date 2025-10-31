# auth_storage.py
# Secure user and SMTP secret storage helpers.
# Requirements: pip install passlib[bcrypt] cryptography keyring filelock
#
# Exports:
#   init_user_store(users_file)
#   create_user(username, password, fullname, require_password_change=False)
#   verify_user(username, password) -> bool
#   change_password(username, new_password)
#   user_requires_password_change(username) -> bool
#   set_smtp_password_record(account, password) -> record to store in email_config['password']
#   get_smtp_password_from_record(record) -> plaintext password

import os
import json
import logging
from typing import Dict
from passlib.context import CryptContext

# file_locking helpers
try:
    from file_locking import load_json_locked, save_json_locked
except Exception:
    # Minimal fallbacks (no locking)
    def load_json_locked(path, default=None):
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return default
        return default
    def save_json_locked(path, obj):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, default=str)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)

logger = logging.getLogger("auth_storage")
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DEFAULT_USERS_FILE = os.environ.get("USERS_FILE", os.path.join(BASE_DIR, "data", "users.json"))

MASTER_PASSPHRASE = os.environ.get("AFMDW_MASTER_PASSPHRASE", "").strip() or None

CRYPTO_AVAILABLE = False
if MASTER_PASSPHRASE:
    try:
        from cryptography.fernet import Fernet
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.backends import default_backend
        import base64
        CRYPTO_AVAILABLE = True
    except Exception:
        logger.warning("cryptography unavailable; reversible secret encryption disabled")
        CRYPTO_AVAILABLE = False

try:
    import keyring
    KEYRING_AVAILABLE = True
except Exception:
    KEYRING_AVAILABLE = False

# encryption helpers
if CRYPTO_AVAILABLE:
    import base64
    def _derive_fernet_key(passphrase: str, salt: bytes) -> bytes:
        kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=390000, backend=default_backend())
        key = kdf.derive(passphrase.encode("utf-8"))
        return base64.urlsafe_b64encode(key)
    def encrypt_secret(plain: str) -> Dict[str, str]:
        salt = os.urandom(16)
        key = _derive_fernet_key(MASTER_PASSPHRASE, salt)
        token = Fernet(key).encrypt(plain.encode("utf-8"))
        return {"method": "passphrase", "salt": salt.hex(), "token": token.hex()}
    def decrypt_secret(enc: Dict[str, str]) -> str:
        try:
            if not enc:
                return ""
            if enc.get("method") == "passphrase":
                salt = bytes.fromhex(enc.get("salt", ""))
                token = bytes.fromhex(enc.get("token", ""))
                key = _derive_fernet_key(MASTER_PASSPHRASE, salt)
                return Fernet(key).decrypt(token).decode("utf-8")
            return ""
        except Exception:
            logger.exception("Failed to decrypt secret")
            return ""
else:
    def encrypt_secret(plain: str) -> Dict[str, str]:
        return {"method": "plain", "value": plain}
    def decrypt_secret(enc: Dict[str, str]) -> str:
        if not enc:
            return ""
        if isinstance(enc, dict):
            return enc.get("value", "") or ""
        return ""

# user storage functions
def load_users(users_file: str = DEFAULT_USERS_FILE) -> Dict[str, Dict]:
    users = load_json_locked(users_file, {})
    if not isinstance(users, dict):
        users = {}
    return users

def save_users(users: Dict[str, Dict], users_file: str = DEFAULT_USERS_FILE) -> None:
    os.makedirs(os.path.dirname(users_file), exist_ok=True)
    save_json_locked(users_file, users)

def ensure_admin(users_file: str = DEFAULT_USERS_FILE) -> None:
    users = load_users(users_file)
    if "administrator" not in users:
        pwd = "Schalk@p1976"
        users["administrator"] = {"password": pwd_context.hash(pwd), "fullname": "Administrator", "require_password_change": True}
        save_users(users, users_file)
        logger.info("Created default administrator account")

def create_user(username: str, password: str, fullname: str = "", require_password_change: bool = False, users_file: str = DEFAULT_USERS_FILE) -> None:
    users = load_users(users_file)
    if username in users:
        raise ValueError("username exists")
    users[username] = {"password": pwd_context.hash(password), "fullname": fullname, "require_password_change": bool(require_password_change)}
    save_users(users, users_file)
    logger.info("Created user %s", username)

def verify_user(username: str, password: str, users_file: str = DEFAULT_USERS_FILE) -> bool:
    users = load_users(users_file)
    rec = users.get(username)
    if not rec:
        return False
    stored = rec.get("password", "")
    try:
        if pwd_context.identify(stored):
            return pwd_context.verify(password, stored)
    except Exception:
        pass
    # legacy plaintext fallback — migrate immediately
    if stored == password:
        rec["password"] = pwd_context.hash(password)
        users[username] = rec
        save_users(users, users_file)
        logger.info("Migrated plaintext password to hashed for user %s", username)
        return True
    return False

def change_password(username: str, new_password: str, users_file: str = DEFAULT_USERS_FILE) -> None:
    users = load_users(users_file)
    if username not in users:
        raise ValueError("user not found")
    users[username]["password"] = pwd_context.hash(new_password)
    users[username]["require_password_change"] = False
    save_users(users, users_file)
    logger.info("Changed password for user %s", username)

def user_requires_password_change(username: str, users_file: str = DEFAULT_USERS_FILE) -> bool:
    users = load_users(users_file)
    return bool(users.get(username, {}).get("require_password_change", False))

# SMTP secret helpers
SMTP_KEYRING_SERVICE = "afmdw_smtp"

def set_smtp_password_record(account: str, password: str):
    """
    Create a safe record to store in email_config['password'].
    Prefer encryption with master passphrase; fallback to keyring; otherwise plain (not recommended).
    """
    if MASTER_PASSPHRASE and CRYPTO_AVAILABLE:
        return encrypt_secret(password)
    if KEYRING_AVAILABLE:
        try:
            keyring.set_password(SMTP_KEYRING_SERVICE, account, password)
            return {"method": "keyring", "account": account}
        except Exception:
            logger.exception("keyring set failed")
    logger.warning("Storing SMTP password as plain (no secure store available)")
    return {"method": "plain", "value": password}

def get_smtp_password_from_record(record) -> str:
    if isinstance(record, dict):
        method = record.get("method")
        if method == "passphrase":
            return decrypt_secret(record)
        if method == "keyring":
            acct = record.get("account")
            if KEYRING_AVAILABLE and acct:
                try:
                    return keyring.get_password(SMTP_KEYRING_SERVICE, acct) or ""
                except Exception:
                    logger.exception("keyring get failed")
                    return ""
        if method == "plain":
            return record.get("value", "") or ""
        return ""
    elif isinstance(record, str):
        return record
    return ""

def migrate_plaintext_users_to_hashed(users_file: str = DEFAULT_USERS_FILE) -> None:
    users = load_users(users_file)
    changed = False
    for username, rec in list(users.items()):
        pwd = rec.get("password", "")
        if not pwd:
            continue
        try:
            if not pwd_context.identify(pwd):
                users[username]["password"] = pwd_context.hash(pwd)
                changed = True
                logger.info("Migrated user %s to hashed password", username)
        except Exception:
            users[username]["password"] = pwd_context.hash(pwd)
            changed = True
            logger.info("Migrated user %s (fallback)", username)
    if changed:
        save_users(users, users_file)

def init_user_store(users_file: str = DEFAULT_USERS_FILE):
    os.makedirs(os.path.dirname(users_file), exist_ok=True)
    ensure_admin(users_file)

# initialize
init_user_store()