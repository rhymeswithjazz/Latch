#!/usr/bin/env python3
"""Publish one Sparkle feed from the fork's published personal releases."""

import argparse
import base64
import json
from pathlib import Path
import subprocess

from release_support import REPOSITORY, FEED_URL
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def gh_json(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def published_releases():
    pages = gh_json("api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100")
    return [release for page in pages for release in page
            if not release["draft"] and release["tag_name"].startswith("personal-")]


def read_item(xml, release):
    root = ET.fromstring(xml)
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Each personal release must contain exactly one appcast item")
    item = items[0]
    version = item.findtext(f"{{{SPARKLE}}}version", "")
    if not version.isascii() or not version.isdecimal() or int(version) <= 1:
        raise ValueError("Personal build numbers must be integers greater than 1")
    if release["tag_name"] != f"personal-{version}":
        raise ValueError("Release tag does not match the appcast build number")
    channel = item.findtext(f"{{{SPARKLE}}}channel")
    if channel != ("beta" if release["prerelease"] else None):
        raise ValueError("Appcast channel does not match the GitHub prerelease setting")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update download")
    expected_name = f"Latch-{version}.zip"
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/personal-{version}/{expected_name}"
    if enclosure.get("url") != expected_url:
        raise ValueError("Update download must point to Latch's matching release")
    signature = base64.b64decode(enclosure.get(f"{{{SPARKLE}}}edSignature", ""), validate=True)
    if len(signature) != 64:
        raise ValueError("Missing or invalid EdDSA signature")
    assets = [asset for asset in release["assets"] if asset["name"] == expected_name]
    if len(assets) != 1 or int(enclosure.get("length", "0")) != assets[0]["size"]:
        raise ValueError("ZIP asset is missing or its length differs from the signed appcast")
    if item.find(f"{{{SPARKLE}}}deltas") is not None:
        raise ValueError("Personal releases currently support full ZIP updates only")
    return int(version), item


def build_feed(release_items):
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Latch personal builds"
    ET.SubElement(channel, "link").text = FEED_URL
    ET.SubElement(channel, "description").text = "Updates for Latch."
    versions = set()
    validated = []
    for xml, release in release_items:
        version, item = read_item(xml, release)
        if version in versions:
            raise ValueError(f"Duplicate build number: {version}")
        versions.add(version)
        validated.append((version, item))
    for _, item in sorted(validated, key=lambda entry: entry[0], reverse=True):
        channel.append(item)
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    entries = []
    for release in published_releases():
        assets = [asset for asset in release["assets"] if asset["name"] == "appcast.xml"]
        if len(assets) != 1:
            raise ValueError(f"{release['tag_name']} needs exactly one appcast.xml asset")
        xml = subprocess.check_output([
            "gh", "api", "-H", "Accept: application/octet-stream",
            f"repos/{REPOSITORY}/releases/assets/{assets[0]['id']}",
        ])
        entries.append((xml, release))
    feed = build_feed(entries)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(feed)
    print(f"Wrote {args.output} with {len(entries)} releases")


if __name__ == "__main__":
    main()
