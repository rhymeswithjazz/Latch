#!/usr/bin/env python3
"""Package the generated Latch artwork into a macOS icon bundle."""
from pathlib import Path
import subprocess
import struct
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def package_icon():
    with tempfile.TemporaryDirectory(prefix="latch-icon-") as directory:
        iconset = Path(directory) / "Latch.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                suffix = "@2x" if scale == 2 else ""
                output = iconset / f"icon_{points}x{points}{suffix}.png"
                subprocess.run(["sips", "-z", str(pixels), str(pixels), str(ROOT / "Resources/Latch.png"),
                                "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
        entries = {
            "icp4": "icon_16x16.png", "icp5": "icon_32x32.png", "icp6": "icon_32x32@2x.png",
            "ic07": "icon_128x128.png", "ic08": "icon_256x256.png", "ic09": "icon_512x512.png",
            "ic10": "icon_512x512@2x.png", "ic11": "icon_16x16@2x.png", "ic12": "icon_32x32@2x.png",
            "ic13": "icon_128x128@2x.png", "ic14": "icon_256x256@2x.png",
        }
        chunks = []
        for kind, name in entries.items():
            data = (iconset / name).read_bytes()
            chunks.append(kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
        body = b"".join(chunks)
        (ROOT / "Resources/Latch.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    package_icon()
