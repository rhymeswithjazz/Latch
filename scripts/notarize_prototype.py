#!/usr/bin/env python3
"""Sign, notarize, and archive a prototype without publishing it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

from build_app import ROOT, BUNDLE_ID, build_app, run
from personal_release import sign_app

TEAM_ID = "T4VMW3KDVX"


def source_hashes():
    files = [ROOT / "Package.swift"]
    for directory in ("Sources", "Resources", "scripts", "Tests", "docs"):
        files += [path for path in (ROOT / directory).rglob("*")
                  if path.is_file() and "__pycache__" not in path.parts]
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(files)}


def bundle_hashes(app):
    return {str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(app.rglob("*")) if path.is_file()}


def verify_submitted_bundle(app, output):
    expected = json.loads((output / "submitted-files.json").read_text())
    if bundle_hashes(app) != expected:
        raise ValueError("The submitted app changed; package a new build")


def signing_identity():
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
    matches = re.findall(r'([A-Fa-f0-9]{40}) "Developer ID Application: [^"\n]+ \(' + TEAM_ID + r'\)"', identities)
    if len(matches) != 1:
        raise ValueError(f"Expected one Developer ID identity for team {TEAM_ID}; found {len(matches)}")
    return matches[0]


def validate_bundle(app, version, build):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": version,
                "CFBundleVersion": str(build), "UnlockerDiagnosticOnly": False}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("App metadata does not match the release")
    architectures = run("lipo", "-archs", str(app / "Contents/MacOS/Latch"), capture=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("The prototype must support Apple Silicon and Intel")


def package(args):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version) or args.build < 1:
        raise ValueError("Use a three-part version and a positive build number")
    identity = signing_identity()
    before = source_hashes()
    output = ROOT / f"build/prototypes/{args.build}"
    output.mkdir(parents=True, exist_ok=False)
    (output / "sources.json").write_text(json.dumps(before, indent=2) + "\n")
    app = build_app(output / "Latch.app", universal=True, version=args.version, build=args.build)
    validate_bundle(app, args.version, args.build)
    if source_hashes() != before:
        raise ValueError("Source changed while building; package a new build")
    sign_app(app, identity)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    (output / "submitted-files.json").write_text(json.dumps(bundle_hashes(app), indent=2) + "\n")
    submission = output / "submission.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submission))
    response = json.loads(run("xcrun", "notarytool", "submit", str(submission), "--keychain-profile",
                              args.notary_profile, "--output-format", "json", capture=True))
    (output / "submission.json").write_text(json.dumps(response, indent=2) + "\n")
    print(f"Submitted {response['id']}. Finish with: python3 scripts/notarize_prototype.py finish {args.build}")


def finish(args):
    if args.build < 1:
        raise ValueError("Use a positive build number")
    output = ROOT / f"build/prototypes/{args.build}"
    submission = json.loads((output / "submission.json").read_text())
    result = json.loads(run("xcrun", "notarytool", "info", submission["id"], "--keychain-profile",
                           args.notary_profile, "--output-format", "json", capture=True))
    (output / "notarization.json").write_text(json.dumps(result, indent=2) + "\n")
    if result.get("status") != "Accepted":
        raise ValueError(f"Notarization status: {result.get('status')}. Recheck when complete; inspect notarytool log on failure.")
    app = output / "Latch.app"
    archive = output / f"Latch-prototype-{args.build}.zip"
    if archive.exists():
        raise ValueError("The final archive already exists; do not overwrite distributed builds")
    verify_submitted_bundle(app, output)
    run("xcrun", "stapler", "staple", str(app))
    run("xcrun", "stapler", "validate", str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    run("spctl", "--assess", "--type", "execute", "--verbose", str(app))
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
    manifest = {"archive": archive.name, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "notarizationID": submission["id"], "diagnosticOnly": False}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Notarized prototype: {archive}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    child = commands.add_parser("package")
    child.add_argument("--version", default="0.1.0")
    child.add_argument("--build", type=int, required=True)
    child.add_argument("--notary-profile", default="netnewswire-notary")
    child = commands.add_parser("finish")
    child.add_argument("build", type=int)
    child.add_argument("--notary-profile", default="netnewswire-notary")
    arguments = parser.parse_args()
    try:
        {"package": package, "finish": finish}[arguments.command](arguments)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
