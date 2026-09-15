import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notarize_prototype as release


class PrototypeReleaseTests(unittest.TestCase):
    def test_rejects_modified_submitted_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            app = output / "Latch.app"
            app.mkdir()
            executable = app / "executable"
            executable.write_bytes(b"original")
            (output / "submitted-files.json").write_text(json.dumps(release.bundle_hashes(app)))
            release.verify_submitted_bundle(app, output)
            executable.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "changed"):
                release.verify_submitted_bundle(app, output)

    def test_refuses_wrong_mode_or_identity_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Latch.app"
            (app / "Contents").mkdir(parents=True)
            path = app / "Contents/Info.plist"
            info = {"CFBundleIdentifier": release.BUNDLE_ID, "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "1", "UnlockerDiagnosticOnly": False}
            path.write_bytes(plistlib.dumps(info))
            with patch.object(release, "run", return_value="arm64 x86_64"):
                release.validate_bundle(app, "0.1.0", 1)
                info["UnlockerDiagnosticOnly"] = True
                path.write_bytes(plistlib.dumps(info))
                with self.assertRaisesRegex(ValueError, "metadata"):
                    release.validate_bundle(app, "0.1.0", 1)
                info["UnlockerDiagnosticOnly"] = False
                info["CFBundleIdentifier"] = "another.app"
                path.write_bytes(plistlib.dumps(info))
                with self.assertRaisesRegex(ValueError, "metadata"):
                    release.validate_bundle(app, "0.1.0", 1)

    def test_requires_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Latch.app"
            (app / "Contents").mkdir(parents=True)
            info = {"CFBundleIdentifier": release.BUNDLE_ID, "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "1", "UnlockerDiagnosticOnly": False}
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            with patch.object(release, "run", return_value="arm64"):
                with self.assertRaisesRegex(ValueError, "Intel"):
                    release.validate_bundle(app, "0.1.0", 1)

    def test_notarization_in_progress_cannot_create_archive(self):
        from argparse import Namespace
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "build/prototypes/1"
            output.mkdir(parents=True)
            (output / "submission.json").write_text(json.dumps({"id": "submission-id"}))
            with patch.object(release, "ROOT", root), patch.object(release, "run", return_value='{"status":"In Progress"}') as run:
                with self.assertRaisesRegex(ValueError, "In Progress"):
                    release.finish(Namespace(build=1, notary_profile="test"))
                self.assertEqual(run.call_count, 1)
                self.assertFalse((output / "Latch-prototype-1.zip").exists())

    def test_signing_identity_does_not_choose_development_certificate(self):
        listing = ('A' * 40 + ' "Apple Development: Somebody (T4VMW3KDVX)"\n'
                   + 'B' * 40 + ' "Developer ID Application: Somebody (T4VMW3KDVX)"')
        with patch.object(release, "run", return_value=listing):
            self.assertEqual(release.signing_identity(), 'B' * 40)


if __name__ == "__main__":
    unittest.main()
