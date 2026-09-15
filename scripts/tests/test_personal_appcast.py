import base64
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from personal_appcast import SPARKLE, build_feed, published_releases, read_item


def release_item(build=8001, beta=False):
    channel = "<sparkle:channel>beta</sparkle:channel>" if beta else ""
    signature = base64.b64encode(bytes(64)).decode()
    name = f"Latch-{build}.zip"
    xml = f'''<rss xmlns:sparkle="{SPARKLE}"><channel><item>
        <sparkle:version>{build}</sparkle:version>{channel}
        <enclosure url="https://github.com/rhymeswithjazz/Latch/releases/download/personal-{build}/{name}"
                   length="123" sparkle:edSignature="{signature}" />
        </item></channel></rss>'''
    release = {"tag_name": f"personal-{build}", "prerelease": beta,
               "assets": [{"name": name, "size": 123}]}
    return xml, release


class PersonalAppcastTests(unittest.TestCase):
    def test_feed_sorts_builds_and_keeps_stable_and_beta(self):
        root = ET.fromstring(build_feed([release_item(8001), release_item(8002, beta=True)]))
        items = root.findall("./channel/item")
        self.assertEqual([item.findtext(f"{{{SPARKLE}}}version") for item in items], ["8002", "8001"])
        self.assertEqual(items[0].findtext(f"{{{SPARKLE}}}channel"), "beta")
        self.assertIsNone(items[1].find(f"{{{SPARKLE}}}channel"))

    def test_rejects_upstream_download(self):
        xml, release = release_item()
        with self.assertRaisesRegex(ValueError, "Latch"):
            read_item(xml.replace("rhymeswithjazz/Latch", "Ranchero-Software/Latch"), release)

    def test_rejects_missing_zip_and_mismatched_size(self):
        xml, release = release_item()
        for assets in ([], [{"name": "Latch-8001.zip", "size": 999}]):
            release["assets"] = assets
            with self.assertRaisesRegex(ValueError, "ZIP asset"):
                read_item(xml, release)

    def test_rejects_beta_as_stable(self):
        xml, release = release_item(beta=True)
        release["prerelease"] = False
        with self.assertRaisesRegex(ValueError, "channel"):
            read_item(xml, release)

    def test_rejects_missing_signature(self):
        xml, release = release_item()
        root = ET.fromstring(xml)
        del root.find("./channel/item/enclosure").attrib[f"{{{SPARKLE}}}edSignature"]
        with self.assertRaisesRegex(ValueError, "signature"):
            read_item(ET.tostring(root), release)

    def test_rejects_duplicate_builds_and_wrong_tags(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            build_feed([release_item(), release_item()])
        xml, release = release_item()
        release["tag_name"] = "personal-9999"
        with self.assertRaisesRegex(ValueError, "tag"):
            read_item(xml, release)

    def test_rejects_old_builds(self):
        with self.assertRaisesRegex(ValueError, "greater than"):
            read_item(*release_item(1))

    def test_no_releases_produces_valid_empty_feed(self):
        self.assertEqual(ET.fromstring(build_feed([])).findall("./channel/item"), [])

    def test_drafts_and_upstream_tags_are_excluded_across_pages(self):
        with patch("personal_appcast.gh_json", return_value=[[
            {"draft": True, "tag_name": "personal-8001"},
            {"draft": False, "tag_name": "mac-7.1.4"},
        ], [{"draft": False, "tag_name": "personal-8002"}]]):
            self.assertEqual([release["tag_name"] for release in published_releases()], ["personal-8002"])


if __name__ == "__main__":
    unittest.main()
