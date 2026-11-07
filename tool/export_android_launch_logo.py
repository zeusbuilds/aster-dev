#!/usr/bin/env python3
"""Render Android native opening artwork through the unchanged Flutter painter.

Android 12's no-background launch-icon viewport is a 288 dp square with a
192 dp safe circle. The visible mark retains Flutter's own width and is centered
independently of its asymmetric shadows. These resources are not launcher icons.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

# Reuse the audited Dart parser and unsupported-algorithm rejection policy.
from export_aster_launch_logo import ExportError, OpeningMark, read_mark

ROOT = Path(__file__).resolve().parents[1]
RENDERER = "tool/render_android_launch_logo_test.dart"
RECEIPT = "tool/launch_artwork/android-launch-opening.json"
VIEWPORT_DP = 288
SAFE_DIAMETER_DP = 192
RESOURCE = "aster_launch_opening.png"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resource_path(density: str) -> str:
    return f"android/app/src/main/res/drawable-{density}/{RESOURCE}"


def render_spec(mark: OpeningMark) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sourceSha256": mark.source_hashes,
        "rendererTool": RENDERER,
        "rendererToolSha256": _sha((ROOT / RENDERER).read_bytes()),
        "viewportDp": VIEWPORT_DP,
        "safeDiameterDp": SAFE_DIAMETER_DP,
        "visibleMarkWidthDp": float(mark.visible_width),
        "markSourceUnits": [float(mark.width), float(mark.height)],
        "blueArgb": "FF" + mark.blue[1:],
        "sourcePose": {"rotation": 0, "expansion": 0, "colorProgress": 0},
        "outputs": [
            {"density": name, "scale": scale, "path": resource_path(name),
             "pixelSize": [round(VIEWPORT_DP * scale)] * 2}
            for name, scale in DENSITIES.items()
        ],
        "outputReceipt": RECEIPT,
    }


def spec_bytes(mark: OpeningMark) -> bytes:
    return (json.dumps(render_spec(mark), indent=2, sort_keys=True) + "\n").encode()


def _png_rgba(png: bytes) -> tuple[int, int, bytes]:
    """Decode 8-bit RGBA PNGs with standard-library-only integrity checks."""
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        raise ExportError("Android opening artwork must be a PNG")
    offset, compressed, header, ended = 8, bytearray(), None, False
    while offset < len(png):
        if offset + 12 > len(png):
            raise ExportError("Truncated Android opening PNG")
        length = struct.unpack(">I", png[offset:offset + 4])[0]
        kind = png[offset + 4:offset + 8]
        end = offset + 8 + length
        if end + 4 > len(png):
            raise ExportError("Truncated Android opening PNG chunk")
        body = png[offset + 8:end]
        if zlib.crc32(kind + body) & 0xffffffff != struct.unpack(">I", png[end:end + 4])[0]:
            raise ExportError("Android opening PNG checksum mismatch")
        if header is None and kind != b"IHDR":
            raise ExportError("Android opening PNG has no leading IHDR")
        if kind == b"IHDR":
            if header is not None or length != 13:
                raise ExportError("Invalid Android opening PNG header")
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            if length != 0 or end + 4 != len(png):
                raise ExportError("Invalid Android opening PNG end")
            ended = True
            break
        offset = end + 4
    if not ended or header is None:
        raise ExportError("Incomplete Android opening PNG")
    width, height, depth, color, compression, filtering, interlace = header
    if not (0 < width <= 4096 and 0 < height <= 4096
            and (depth, color, compression, filtering, interlace) == (8, 6, 0, 0, 0)):
        raise ExportError("Expected a noninterlaced 8-bit RGBA opening PNG")
    stride = width * 4
    expected_length = height * (stride + 1)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(compressed, expected_length + 1)
    if not decoder.eof or decoder.unused_data or len(raw) != expected_length:
        raise ExportError("Invalid Android opening PNG pixel stream")
    pixels, previous = bytearray(), bytearray(stride)
    for row in range(height):
        start = row * (stride + 1)
        mode, scanline = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if mode > 4:
            raise ExportError("Unsupported PNG scanline filter")
        for x in range(stride):
            a = scanline[x - 4] if x >= 4 else 0
            b = previous[x]
            c = previous[x - 4] if x >= 4 else 0
            if mode == 1:
                predictor = a
            elif mode == 2:
                predictor = b
            elif mode == 3:
                predictor = (a + b) // 2
            elif mode == 4:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                predictor = (a, b, c)[distances.index(min(distances))]
            else:
                predictor = 0
            scanline[x] = (scanline[x] + predictor) & 255
        pixels.extend(scanline)
        previous = scanline
    return width, height, bytes(pixels)


def inspect_png(png: bytes, scale: float, mark: OpeningMark) -> dict[str, object]:
    width, height, pixels = _png_rgba(png)
    expected = round(VIEWPORT_DP * scale)
    if (width, height) != (expected, expected):
        raise ExportError("Android opening PNG dimensions do not match its density")
    blue = tuple(bytes.fromhex(mark.blue[1:]))
    counts = {"nonTransparentPixels": 0, "opaqueBluePixels": 0,
              "translucentBluePixels": 0, "blackShadowPixels": 0}
    bounds = [width, height, -1, -1]
    colored_bounds = [width, height, -1, -1]
    radius = 0.0
    for index in range(0, len(pixels), 4):
        red, green, channel_blue, alpha = pixels[index:index + 4]
        if not alpha:
            continue
        x, y = (index // 4) % width, (index // 4) // width
        counts["nonTransparentPixels"] += 1
        bounds = [min(bounds[0], x), min(bounds[1], y), max(bounds[2], x), max(bounds[3], y)]
        logical_radius = math.hypot((x + .5) / scale - VIEWPORT_DP / 2,
                                    (y + .5) / scale - VIEWPORT_DP / 2)
        radius = max(radius, logical_radius)
        if logical_radius > SAFE_DIAMETER_DP / 2:
            raise ExportError("Android opening artwork exceeds the unmasked safe circle")
        if (red, green, channel_blue) == (0, 0, 0):
            counts["blackShadowPixels"] += 1
            if alpha == 255:
                raise ExportError("Opening shadow unexpectedly became opaque")
        else:
            colored_bounds = [min(colored_bounds[0], x), min(colored_bounds[1], y),
                              max(colored_bounds[2], x), max(colored_bounds[3], y)]
            if alpha == 255:
                if any(abs(actual - expected) > 1
                       for actual, expected in zip((red, green, channel_blue), blue)):
                    raise ExportError("Opaque opening ink does not retain Flutter's source blue")
                counts["opaqueBluePixels"] += 1
            else:
                counts["translucentBluePixels"] += 1
    if any(value <= 0 for value in counts.values()):
        raise ExportError("Opening PNG must retain opaque ink, translucent gradient and outside shadow")
    if bounds[0] <= 0 or bounds[1] <= 0 or bounds[2] >= width - 1 or bounds[3] >= height - 1:
        raise ExportError("Opening PNG clips its artwork at the image border")
    return {**counts, "nonTransparentBoundsPixels": bounds,
            "coloredBoundsPixels": colored_bounds,
            "maximumRadiusDp": round(radius, 6)}


def verify_outputs(root: Path, mark: OpeningMark) -> dict[str, object]:
    try:
        metadata = json.loads((root / RECEIPT).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ExportError("Generate Android artwork with --render --flutter /path/to/flutter") from error
    spec = render_spec(mark)
    expected_fields = {key: spec[key] for key in (
        "schemaVersion", "sourceSha256", "rendererTool", "rendererToolSha256",
        "viewportDp", "safeDiameterDp", "visibleMarkWidthDp", "markSourceUnits", "blueArgb", "sourcePose",
    )}
    expected_fields.update({"renderSpecSha256": _sha(spec_bytes(mark)), "colorSpace": "sRGB"})
    for key, expected in expected_fields.items():
        if metadata.get(key) != expected:
            raise ExportError(f"Android opening artwork provenance is stale or invalid ({key}); regenerate with --render")
    outputs = metadata.get("outputs")
    if not isinstance(outputs, list) or len(outputs) != len(DENSITIES):
        raise ExportError("Android opening artwork density set is incomplete")
    for expected, actual in zip(spec["outputs"], outputs):
        if not isinstance(actual, dict) or any(actual.get(k) != v for k, v in expected.items()):
            raise ExportError("Android opening artwork density path/size is invalid")
        try:
            png = (root / expected["path"]).read_bytes()
        except OSError as error:
            raise ExportError(f"Missing Android opening PNG: {expected['path']}") from error
        if actual.get("pngSha256") != _sha(png):
            raise ExportError("Android opening PNG hash does not match the painter receipt")
        inspect_png(png, expected["scale"], mark)
    return metadata


def render(root: Path, mark: OpeningMark, flutter: str | None) -> None:
    executable = flutter or shutil.which("flutter")
    if executable is None:
        local = root / ".fvm/flutter_sdk/bin/flutter"
        executable = str(local) if local.exists() else None
    if executable is None:
        raise ExportError("Pass --flutter /path/to/flutter when rendering Android artwork")
    path = root / ".buildlog/native-android-launch-export/render-spec.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(spec_bytes(mark))
    subprocess.run([executable, "test", "--no-pub", "--concurrency=1",
                    f"--dart-define=ASTER_ANDROID_LAUNCH_SPEC={path}", RENDERER],
                   cwd=root, check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", help="Render every density through the actual Flutter painter")
    parser.add_argument("--check", action="store_true", help="Verify source, renderer and every output without writing")
    parser.add_argument("--flutter", help="Flutter executable for --render")
    args = parser.parse_args(argv)
    if args.check and args.render:
        parser.error("--check never writes artifacts; use --render separately")
    try:
        mark = read_mark(ROOT)
        if args.render:
            render(ROOT, mark, args.flutter)
        verify_outputs(ROOT, mark)
        print("Android opening artwork matches the unchanged Flutter painter at all five density scales.")
        return 0
    except (ExportError, OSError, ValueError, subprocess.CalledProcessError, zlib.error) as error:
        print(f"Android launch artwork export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
