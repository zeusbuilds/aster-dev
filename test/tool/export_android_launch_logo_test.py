#!/usr/bin/env python3
"""Android native artwork provenance, density and masking contracts."""
from __future__ import annotations

import contextlib
import io
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
import export_android_launch_logo as EXPORT


def png_rgba(width: int, height: int, pixels: bytes) -> bytes:
    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff))
    rows = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4]
                    for y in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


class AndroidLaunchExportTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for path in [*EXPORT.read_mark(ROOT).source_hashes, EXPORT.RENDERER,
                     EXPORT.RECEIPT, *(EXPORT.resource_path(d) for d in EXPORT.DENSITIES)]:
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / path).read_bytes())
        self.mark = EXPORT.read_mark(self.root)

    def replace(self, relative, before, after):
        path = self.root / relative
        text = path.read_text()
        self.assertEqual(text.count(before), 1)
        path.write_text(text.replace(before, after))

    def metadata(self):
        return json.loads((self.root / EXPORT.RECEIPT).read_text())

    def write_metadata(self, data):
        (self.root / EXPORT.RECEIPT).write_text(json.dumps(data))

    def mdpi(self):
        return (self.root / EXPORT.resource_path("mdpi")).read_bytes()

    def test_every_shipped_density_matches_flutter_sources_renderer_and_png_hashes(self):
        with patch.object(EXPORT, "ROOT", self.root):
            receipt = EXPORT.verify_outputs(self.root, self.mark)
        self.assertEqual(len(receipt["outputs"]), 5)
        self.assertEqual([o["pixelSize"][0] for o in receipt["outputs"]],
                         [288, 432, 576, 864, 1152])
        self.assertEqual(receipt["sourcePose"], {"rotation": 0, "expansion": 0, "colorProgress": 0})
        self.assertEqual(receipt["visibleMarkWidthDp"], 160)

    def test_visible_mark_is_centered_at_160_dp_without_recentering_the_shadow(self):
        for density, scale in EXPORT.DENSITIES.items():
            result = EXPORT.inspect_png((self.root / EXPORT.resource_path(density)).read_bytes(),
                                        scale, self.mark)
            left, top, right, bottom = result["coloredBoundsPixels"]
            self.assertEqual(right - left + 1, round(160 * scale))
            self.assertAlmostEqual((left + right + 1) / 2 / scale, 144)
            self.assertLessEqual(abs((top + bottom + 1) / 2 - 144 * scale), .5)
            self.assertLess(result["maximumRadiusDp"], 96)
            # The shadows naturally extend further below the mark; they must
            # not shift the centered visible silhouette to compensate.
            shadow_top = result["nonTransparentBoundsPixels"][1]
            shadow_bottom = result["nonTransparentBoundsPixels"][3]
            self.assertGreater(shadow_bottom - bottom, top - shadow_top)

    def test_numeric_painter_change_makes_existing_art_stale(self):
        self.replace("lib/shared/branding/aster_launch_logo.dart",
                     "_bottomOpacity = 0.3", "_bottomOpacity = 0.25")
        with patch.object(EXPORT, "ROOT", self.root):
            with self.assertRaisesRegex(EXPORT.ExportError, "sourceSha256"):
                EXPORT.verify_outputs(self.root, EXPORT.read_mark(self.root))

    def test_unsupported_geometry_change_is_rejected_by_shared_parser(self):
        self.replace("lib/shared/branding/aster_logo_geometry.dart",
                     "PathOperation.union", "PathOperation.intersect")
        with self.assertRaisesRegex(EXPORT.ExportError, "logo geometry"):
            EXPORT.read_mark(self.root)

    def test_renderer_change_makes_existing_art_stale(self):
        path = self.root / EXPORT.RENDERER
        path.write_text(path.read_text() + "\n// changed renderer\n")
        with patch.object(EXPORT, "ROOT", self.root):
            with self.assertRaisesRegex(EXPORT.ExportError, "rendererToolSha256"):
                EXPORT.verify_outputs(self.root, self.mark)

    def test_changed_png_cannot_pass_its_original_painter_receipt(self):
        path = self.root / EXPORT.resource_path("mdpi")
        path.write_bytes(path.read_bytes() + b"changed")
        with patch.object(EXPORT, "ROOT", self.root):
            with self.assertRaisesRegex(EXPORT.ExportError, "PNG hash"):
                EXPORT.verify_outputs(self.root, self.mark)

    def test_missing_density_is_rejected(self):
        metadata = self.metadata()
        metadata["outputs"].pop()
        self.write_metadata(metadata)
        with patch.object(EXPORT, "ROOT", self.root):
            with self.assertRaisesRegex(EXPORT.ExportError, "density set"):
                EXPORT.verify_outputs(self.root, self.mark)

    def test_density_paths_cannot_alias_launcher_icons(self):
        metadata = self.metadata()
        metadata["outputs"][0]["path"] = "android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
        self.write_metadata(metadata)
        with patch.object(EXPORT, "ROOT", self.root):
            with self.assertRaisesRegex(EXPORT.ExportError, "density path/size"):
                EXPORT.verify_outputs(self.root, self.mark)

    def test_pixels_outside_android_safe_circle_are_rejected(self):
        width, height, pixels = EXPORT._png_rgba(self.mdpi())
        pixels = bytearray(pixels)
        pixels[:4] = bytes([0, 0, 0, 1])
        with self.assertRaisesRegex(EXPORT.ExportError, "safe circle"):
            EXPORT.inspect_png(png_rgba(width, height, pixels), 1, self.mark)

    def test_wrong_opaque_hue_is_rejected_independently_of_metadata(self):
        width, height, pixels = EXPORT._png_rgba(self.mdpi())
        pixels = bytearray(pixels)
        for i in range(0, len(pixels), 4):
            if pixels[i + 3] == 255:
                pixels[i + 1] = 51
                break
        with self.assertRaisesRegex(EXPORT.ExportError, "source blue"):
            EXPORT.inspect_png(png_rgba(width, height, pixels), 1, self.mark)

    def test_missing_outside_shadows_are_rejected(self):
        width, height, pixels = EXPORT._png_rgba(self.mdpi())
        pixels = bytearray(pixels)
        for i in range(0, len(pixels), 4):
            if pixels[i:i + 3] == b"\0\0\0":
                pixels[i + 3] = 0
        with self.assertRaisesRegex(EXPORT.ExportError, "outside shadow"):
            EXPORT.inspect_png(png_rgba(width, height, pixels), 1, self.mark)

    def test_missing_translucent_gradient_is_rejected(self):
        width, height, pixels = EXPORT._png_rgba(self.mdpi())
        pixels = bytearray(pixels)
        for i in range(0, len(pixels), 4):
            if any(pixels[i:i + 3]):
                pixels[i:i + 4] = bytes([0, 26, 255, 255])
        with self.assertRaisesRegex(EXPORT.ExportError, "translucent gradient"):
            EXPORT.inspect_png(png_rgba(width, height, pixels), 1, self.mark)

    def test_png_corruption_is_rejected_before_pixels_are_used(self):
        png = bytearray(self.mdpi())
        png[20] ^= 1
        with self.assertRaisesRegex(EXPORT.ExportError, "checksum"):
            EXPORT.inspect_png(png, 1, self.mark)

    def test_check_reports_changed_art_without_writing_any_file(self):
        path = self.root / EXPORT.resource_path("mdpi")
        path.write_bytes(b"user change")
        before = {str(p.relative_to(self.root)): p.read_bytes()
                  for p in self.root.rglob("*") if p.is_file()}
        with patch.object(EXPORT, "ROOT", self.root):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(EXPORT.main(["--check"]), 1)
        after = {str(p.relative_to(self.root)): p.read_bytes()
                 for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
