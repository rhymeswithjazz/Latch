from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_app import build_app


class BuildAppTests(unittest.TestCase):
    def test_universal_build_preserves_binaries_when_swift_reuses_output_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "Resources"
            resources.mkdir()
            (resources / "Latch.icns").write_bytes(b"icon")
            (resources / "Info.plist").write_bytes(plistlib.dumps({}))
            sparkle = root / "sparkle"
            framework = sparkle / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
            framework.mkdir(parents=True)
            (sparkle / "LICENSE").write_text("license")
            output = root / "shared-output"
            output.mkdir()

            def run(*arguments, **kwargs):
                if arguments[0] == "swift":
                    if "--show-bin-path" in arguments:
                        return str(output)
                    architecture = arguments[arguments.index("--arch") + 1]
                    (output / "Unlocker").write_text(architecture)
                elif arguments[0] == "lipo":
                    binaries = [Path(path).read_text() for path in arguments[2:4]]
                    self.assertEqual(binaries, ["arm64", "x86_64"])
                    Path(arguments[-1]).write_text("universal")
                return ""

            with patch("build_app.ROOT", root), patch("build_app.SPARKLE", sparkle), patch("build_app.run", side_effect=run):
                app = build_app(root / "Latch.app", universal=True, version="0.4.2", build=8)
            self.assertEqual((app / "Contents/MacOS/Latch").read_text(), "universal")
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["CFBundleShortVersionString"], "0.4.2")
            self.assertEqual(info["CFBundleVersion"], "8")
