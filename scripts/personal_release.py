#!/usr/bin/env python3
"""Package a notarized Latch release, then upload it as a separate draft step."""

import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

from build_app import build_app
from personal_appcast import published_releases, read_item, SPARKLE as SPARKLE_NAMESPACE
from release_support import ROOT, REPOSITORY, FEED_URL, TEAM_ID, BUNDLE_ID, KEY_ACCOUNT, SPARKLE, run, public_key, digest


def tools(args):
    return Path(args.sparkle_bin).expanduser().resolve() if args.sparkle_bin else SPARKLE / "bin"


def signing_identity():
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
    matches = re.findall(r'([A-Fa-f0-9]{40}) "Developer ID Application: [^"\n]+ \(' + TEAM_ID + r'\)"', identities)
    if len(matches) != 1:
        raise ValueError(f"Expected one Developer ID Application identity for team {TEAM_ID}; found {len(matches)}")
    return matches[0]


def setup(args):
    run("swift", "package", "--disable-sandbox", "resolve")
    if not args.create_key:
        return
    generator = tools(args) / "generate_keys"
    existing = public_key()
    if existing:
        actual = run(str(generator), "--account", KEY_ACCOUNT, "-p", capture=True)
        if actual != existing:
            raise ValueError("Import Latch's original private key; do not replace the published key")
    else:
        run(str(generator), "--account", KEY_ACCOUNT)
        actual = run(str(generator), "--account", KEY_ACCOUNT, "-p", capture=True)
        if len(base64.b64decode(actual, validate=True)) != 32:
            raise ValueError("Sparkle returned an invalid public key")
        path = ROOT / "Resources/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["SUPublicEDKey"] = actual
        path.write_bytes(plistlib.dumps(info, sort_keys=False))
    print("Latch's public key matches its private key in Keychain")


def preflight(args):
    for tool in ("swift", "xcrun", "gh", "ditto", "codesign", "security", "lipo", "spctl"):
        if not shutil.which(tool):
            raise ValueError(f"Install {tool}")
    identity = signing_identity()
    for name in ("generate_keys", "generate_appcast", "sign_update"):
        if not (tools(args) / name).is_file():
            raise ValueError("Run setup to resolve the pinned Sparkle tools")
    key = run(str(tools(args) / "generate_keys"), "--account", KEY_ACCOUNT, "-p", capture=True)
    if key != public_key() or len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("Latch's Keychain signing key does not match Resources/Info.plist")
    run("xcrun", "notarytool", "history", "--keychain-profile", args.notary_profile, "--output-format", "json", capture=True)
    repository = json.loads(run("gh", "repo", "view", REPOSITORY, "--json", "nameWithOwner,visibility", capture=True))
    if repository != {"nameWithOwner": REPOSITORY, "visibility": "PUBLIC"}:
        raise ValueError("The configured public GitHub repository is not available")
    print("Developer ID, Sparkle key, notarization credentials, and GitHub repository are ready")
    return identity


def check_build_number(build):
    previous = [7]
    for release in published_releases():
        suffix = release["tag_name"].removeprefix("personal-")
        if not re.fullmatch(r"[1-9][0-9]*", suffix):
            raise ValueError(f"Unexpected personal release tag: {release['tag_name']}")
        previous.append(int(suffix))
    if build <= max(previous):
        raise ValueError(f"Build number must exceed {max(previous)}")


def sign_app(app, identity):
    framework = app / "Contents/Frameworks/Sparkle.framework"
    version = framework / "Versions/B"
    nested = [version / "Autoupdate", version / "Updater.app"]
    nested += sorted((version / "XPCServices").glob("*.xpc"))
    for path in [*nested, framework, app]:
        run("codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp",
            "--preserve-metadata=entitlements", str(path))
    run("codesign", "--verify", "--deep", "--strict", str(app))


def package(args):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        raise ValueError("Use a three-part version such as 0.1.0")
    if not args.notes.is_file():
        raise ValueError("--notes must name a release notes file")
    if run("git", "status", "--porcelain", capture=True):
        raise ValueError("Commit the working tree before packaging a release")
    identity = preflight(args)
    check_build_number(args.build)
    commit = run("git", "rev-parse", "HEAD", capture=True)
    output = ROOT / f"build/personal/releases/{args.build}"
    output.mkdir(parents=True, exist_ok=False)
    app = build_app(output / "export/Latch.app", version=args.version, build=args.build,
                    universal=True, updates=True, log=output / "build.log")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleVersion": str(args.build),
                "CFBundleShortVersionString": args.version, "LatchUpdatesEnabled": True,
                "SUFeedURL": FEED_URL, "SUPublicEDKey": public_key()}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("Built app does not match the release settings")
    architectures = run("lipo", "-archs", str(app / "Contents/MacOS/Latch"), capture=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("The release must support Apple Silicon and Intel")
    sign_app(app, identity)
    submission = output / "notarization.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submission))
    result = json.loads(run("xcrun", "notarytool", "submit", str(submission),
                            "--keychain-profile", args.notary_profile, "--wait", "--output-format", "json", capture=True))
    (output / "notarization.json").write_text(json.dumps(result, indent=2) + "\n")
    if result.get("status") != "Accepted":
        raise ValueError(f"Notarization failed; inspect submission {result.get('id')} with notarytool log")
    run("xcrun", "stapler", "staple", str(app))
    run("xcrun", "stapler", "validate", str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    run("spctl", "--assess", "--type", "execute", "--verbose", str(app))
    payload = output / "payload"
    payload.mkdir()
    zip_path = payload / f"Latch-{args.build}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(zip_path))
    shutil.copyfile(args.notes, zip_path.with_suffix(".md"))
    shutil.copyfile(args.notes, output / "notes.md")
    tag = f"personal-{args.build}"
    command = [str(tools(args) / "generate_appcast"), "--account", KEY_ACCOUNT,
               "--download-url-prefix", f"https://github.com/{REPOSITORY}/releases/download/{tag}/",
               "--link", f"https://github.com/{REPOSITORY}/releases/tag/{tag}",
               "--maximum-deltas", "0", "--embed-release-notes", "-o", str(output / "appcast.xml")]
    if args.beta:
        command += ["--channel", "beta"]
    run(*command, str(payload))
    release = {"tag_name": tag, "prerelease": args.beta,
               "assets": [{"name": zip_path.name, "size": zip_path.stat().st_size}]}
    _, item = read_item((output / "appcast.xml").read_bytes(), release)
    signature = item.find("enclosure").get(f"{{{SPARKLE_NAMESPACE}}}edSignature")
    run(str(tools(args) / "sign_update"), "--account", KEY_ACCOUNT, "--verify", str(zip_path), signature)
    manifest = {"version": args.version, "build": args.build, "beta": args.beta, "commit": commit,
                "repository": REPOSITORY,
                "sha256": {name: digest(output / name) for name in (f"payload/{zip_path.name}", "appcast.xml", "notes.md")}}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Ready for review: {output}\nCreate a draft with: python3 scripts/personal_release.py draft {output}")


def verify_release_tag(build, commit):
    tag = f"personal-{build}"
    ref = f"refs/tags/{tag}"
    output = run("git", "ls-remote", "--tags", f"git@github.com:{REPOSITORY}.git", ref, ref + "^{}", capture=True)
    references = {name: sha for sha, name in (line.split() for line in output.splitlines())}
    actual = references.get(ref + "^{}", references.get(ref))
    if actual is None:
        raise ValueError(f"Push the packaged commit's tag before creating the draft:\n"
                         f"git tag {tag} {commit}\ngit push origin {ref}")
    if actual != commit:
        raise ValueError(f"Remote tag {tag} does not match the packaged commit; do not overwrite it")


def draft(args):
    output = args.directory.resolve()
    manifest = json.loads((output / "release.json").read_text())
    build = manifest["build"]
    expected_names = {f"payload/Latch-{build}.zip", "appcast.xml", "notes.md"}
    if manifest.get("repository") != REPOSITORY or set(manifest["sha256"]) != expected_names:
        raise ValueError("Release manifest does not match Latch's artifacts")
    for name, expected in manifest["sha256"].items():
        path = (output / name).resolve()
        if not path.is_relative_to(output) or digest(path) != expected:
            raise ValueError(f"Release artifact changed after packaging: {name}")
    check_build_number(build)
    verify_release_tag(build, manifest["commit"])
    command = ["gh", "release", "create", f"personal-{build}", "--repo", REPOSITORY,
               "--draft", "--verify-tag",
               "--title", f"Latch {manifest['version']}", "--notes-file", str(output / "notes.md")]
    if manifest["beta"]:
        command += ["--prerelease"]
    run(*command, str(output / "appcast.xml"), str(output / f"payload/Latch-{build}.zip"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("setup", "preflight", "package"):
        child = commands.add_parser(name)
        child.add_argument("--sparkle-bin", default=os.environ.get("SPARKLE_BIN"))
        child.add_argument("--notary-profile", default="netnewswire-notary")
        if name == "setup":
            child.add_argument("--create-key", action="store_true", help="Create Latch's Keychain signing key once and embed its public key")
        if name == "package":
            child.add_argument("--version", required=True)
            child.add_argument("--build", required=True, type=int)
            child.add_argument("--beta", action="store_true")
            child.add_argument("--notes", required=True, type=Path)
    child = commands.add_parser("draft")
    child.add_argument("directory", type=Path)
    args = parser.parse_args()
    {"setup": setup, "preflight": preflight, "package": package, "draft": draft}[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError, KeyError) as error:
        sys.exit(str(error))
