#!/usr/bin/env python3
"""Package the generated Latch artwork into a macOS icon bundle."""
from pathlib import Path
import struct
import subprocess
import tempfile

RESOURCES = Path(__file__).resolve().parents[1] / "Resources"


def resize(directory, pixels, image_format):
    output = directory / f"{pixels}.{image_format}"
    subprocess.run(
        ["sips", "-s", "format", image_format, "-z", str(pixels), str(pixels),
         RESOURCES / "Latch.png", "--out", output],
        check=True, stdout=subprocess.DEVNULL,
    )
    return output


def small_icon_chunks(directory):
    # Finder uses classic RGB and alpha-mask entries for these standard sizes.
    images = [resize(directory, size, "tiff") for size in (16, 32, 48)]
    tiff = directory / "small.tiff"
    icns = directory / "small.icns"
    subprocess.run(["tiffutil", "-catnosizecheck", *images, "-out", tiff], check=True)
    subprocess.run(["tiff2icns", tiff, icns], check=True)
    data = icns.read_bytes()
    offset = 8
    while offset < len(data):
        kind, length = struct.unpack_from(">4sI", data, offset)
        if kind != b"TOC ":  # The native table describes only this subset.
            yield data[offset:offset + length]
        offset += length


def package_icon():
    with tempfile.TemporaryDirectory(prefix="latch-icon-") as directory:
        directory = Path(directory)
        chunks = list(small_icon_chunks(directory))
        # Large standard images and all Retina images use PNG entries.
        sizes = {b"ic07": 128, b"ic08": 256, b"ic09": 512, b"ic10": 1024,
                 b"ic11": 32, b"ic12": 64, b"ic13": 256, b"ic14": 512}
        for kind, pixels in sizes.items():
            data = resize(directory, pixels, "png").read_bytes()
            chunks.append(struct.pack(">4sI", kind, len(data) + 8) + data)
        body = b"".join(chunks)
        (RESOURCES / "Latch.icns").write_bytes(struct.pack(">4sI", b"icns", len(body) + 8) + body)


if __name__ == "__main__":
    package_icon()
