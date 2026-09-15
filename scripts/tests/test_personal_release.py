from pathlib import Path
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from personal_release import check_build_number, draft, sign_app, signing_identity, verify_release_tag
from release_support import digest, REPOSITORY


class PersonalReleaseTests(unittest.TestCase):
    def test_build_numbers_advance_across_channels(self):
        with patch("personal_release.published_releases", return_value=[{"tag_name": "personal-2"}, {"tag_name": "personal-9"}]):
            for build in (1, 2, 7, 9):
                with self.assertRaisesRegex(ValueError, "exceed 9"):
                    check_build_number(build)
            check_build_number(10)

    def test_first_release_must_exceed_development_build(self):
        with patch("personal_release.published_releases", return_value=[]):
            with self.assertRaisesRegex(ValueError, "exceed 7"):
                check_build_number(1)
            check_build_number(8)

    def test_unexpected_personal_tag_stops_packaging(self):
        with patch("personal_release.published_releases", return_value=[{"tag_name": "personal-latest"}]):
            with self.assertRaisesRegex(ValueError, "Unexpected"):
                check_build_number(2)

    def manifest(self, output):
        paths = ["payload/Latch-2.zip", "appcast.xml", "notes.md"]
        for name in paths:
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        manifest = {"repository": REPOSITORY, "build": 2, "version": "0.1.0", "beta": False,
                    "commit": "a" * 40, "sha256": {name: digest(output / name) for name in paths}}
        (output / "release.json").write_text(json.dumps(manifest))
        return manifest

    def test_changed_artifact_is_not_uploaded(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            self.manifest(output)
            (output / "appcast.xml").write_text("changed")
            with patch("personal_release.run") as command:
                with self.assertRaisesRegex(ValueError, "changed after packaging"):
                    draft(SimpleNamespace(directory=output))
                command.assert_not_called()

    def test_missing_hash_and_other_repository_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            for change in ("repository", "sha256"):
                manifest = self.manifest(output)
                if change == "repository":
                    manifest[change] = "other/repo"
                else:
                    del manifest[change]["appcast.xml"]
                (output / "release.json").write_text(json.dumps(manifest))
                with patch("personal_release.run") as command:
                    with self.assertRaisesRegex(ValueError, "manifest"):
                        draft(SimpleNamespace(directory=output))
                    command.assert_not_called()

    def test_upload_is_always_a_draft_at_exact_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = self.manifest(output)
            with patch("personal_release.check_build_number"), patch("personal_release.verify_release_tag") as verify, patch("personal_release.run") as command:
                draft(SimpleNamespace(directory=output))
            arguments = command.call_args.args
            self.assertIn("--draft", arguments)
            self.assertIn("--verify-tag", arguments)
            self.assertNotIn("--target", arguments)
            verify.assert_called_once_with(2, manifest["commit"])
            self.assertNotIn("--prerelease", arguments)

    def test_remote_tag_must_exist_at_packaged_commit(self):
        commit = "a" * 40
        with patch("personal_release.run", return_value=""):
            with self.assertRaisesRegex(ValueError, "Push the packaged commit"):
                verify_release_tag(2, commit)
        with patch("personal_release.run", return_value=f"{'b' * 40}\trefs/tags/personal-2"):
            with self.assertRaisesRegex(ValueError, "does not match"):
                verify_release_tag(2, commit)
        with patch("personal_release.run", return_value=f"{commit}\trefs/tags/personal-2"):
            verify_release_tag(2, commit)

    def test_annotated_tag_is_checked_against_peeled_commit(self):
        commit = "a" * 40
        refs = f"{'b' * 40}\trefs/tags/personal-2\n{commit}\trefs/tags/personal-2^{{}}"
        with patch("personal_release.run", return_value=refs):
            verify_release_tag(2, commit)

    def test_nested_helpers_are_signed_before_framework_and_app(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Latch.app"
            framework = app / "Contents/Frameworks/Sparkle.framework"
            services = framework / "Versions/B/XPCServices"
            services.mkdir(parents=True)
            (services / "Installer.xpc").mkdir()
            with patch("personal_release.run") as command:
                sign_app(app, "identity")
            calls = [call.args for call in command.call_args_list]
            signed = [call[-1] for call in calls if "--sign" in call]
            self.assertEqual(signed[-2:], [str(framework), str(app)])
            self.assertTrue(any(path.endswith("Installer.xpc") for path in signed[:-2]))
            self.assertTrue(all("--timestamp" in call and "runtime" in call for call in calls if "--sign" in call))

    def test_signing_identity_must_match_team(self):
        for identities in ("0 valid identities", '1) ' + 'A' * 40 + ' "Developer ID Application: Someone (OTHERTEAM)"'):
            with patch("personal_release.run", return_value=identities):
                with self.assertRaisesRegex(ValueError, "Expected one"):
                    signing_identity()


if __name__ == "__main__":
    unittest.main()
