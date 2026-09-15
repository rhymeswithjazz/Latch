#!/usr/bin/env python3
"""Assemble a portable Latch app bundle from the pinned Swift package."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import tempfile

from release_support import ROOT, SPARKLE, BUNDLE_ID, run


def build_app(destination, *, version=None, build=None, universal=False, updates=False, log=None):
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    architectures = ["arm64", "x86_64"] if universal else [None]
    with tempfile.TemporaryDirectory(prefix="latch-bundle-", dir=destination.parent) as staging:
        binaries = []
        for architecture in architectures:
            arguments = ["swift", "build", "-c", "release", "--disable-sandbox", "--force-resolved-versions", "--product", "Unlocker"]
            if architecture:
                arguments += ["--arch", architecture]
            run(*arguments, log=log)
            directory = Path(run(*arguments, "--show-bin-path", capture=True))
            binary = Path(staging) / f"Latch-{architecture or 'native'}"
            shutil.copy2(directory / "Unlocker", binary)
            binaries.append(binary)
        app = Path(staging) / "Latch.app"
        macos = app / "Contents/MacOS"
        resources = app / "Contents/Resources"
        frameworks = app / "Contents/Frameworks"
        for directory in (macos, resources, frameworks):
            directory.mkdir(parents=True)
        executable = macos / "Latch"
        if universal:
            run("lipo", "-create", *(str(path) for path in binaries), "-output", str(executable))
        else:
            shutil.copy2(binaries[0], executable)
        executable.chmod(0o755)
        shutil.copy2(ROOT / "Resources/Latch.icns", resources)
        shutil.copy2(SPARKLE / "LICENSE", resources / "Sparkle-LICENSE.txt")
        framework = SPARKLE / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        shutil.copytree(framework, frameworks / "Sparkle.framework", symlinks=True)
        with (ROOT / "Resources/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if version is not None:
            info["CFBundleShortVersionString"] = version
        if build is not None:
            info["CFBundleVersion"] = str(build)
        info["LatchUpdatesEnabled"] = updates
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream, sort_keys=False)
        run("codesign", "--force", "--sign", "-", str(app))
        if destination.exists():
            os.replace(destination, Path(staging) / "previous.app")
        os.replace(app, destination)
    print(f"Built {destination}", flush=True)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--universal", action="store_true")
    arguments = parser.parse_args()
    build_app(ROOT / "build/Latch.app", universal=arguments.universal)
