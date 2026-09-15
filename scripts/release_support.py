"""Shared paths and commands for Latch's local builds and releases."""

import hashlib
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "rhymeswithjazz/Latch"
FEED_URL = "https://rhymeswithjazz.github.io/Latch/appcast.xml"
TEAM_ID = "T4VMW3KDVX"
BUNDLE_ID = "com.rhymeswithjazz.Unlocker"
KEY_ACCOUNT = "com.rhymeswithjazz.Latch"
SPARKLE = ROOT / ".build/artifacts/sparkle/Sparkle"


def run(*command, capture=False, log=None):
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / ".build/clang-cache"))
    if log:
        with log.open("a") as stream:
            subprocess.run(command, cwd=ROOT, env=environment, check=True, stdout=stream, stderr=subprocess.STDOUT)
        return ""
    if capture:
        return subprocess.check_output(command, cwd=ROOT, env=environment, text=True).strip()
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    return ""


def public_key():
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        return plistlib.load(stream)["SUPublicEDKey"]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()
