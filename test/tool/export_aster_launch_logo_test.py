#!/usr/bin/env python3
"""Source drift and geometry contract checks for the native opening SVG."""

import contextlib
import base64
import hashlib
import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "aster_launch_exporter", ROOT / "tool/export_aster_launch_logo.py"
)
EXPORT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = EXPORT
SPEC.loader.exec_module(EXPORT)
SVG_NS = {"s": "http://www.w3.org/2000/svg"}


class LaunchSvgExportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Deliberately provide only Dart sources. No existing native, Figma or
        # canonical SVG is available for an accidental copied-artwork fallback.
        for relative in [EXPORT.GEOMETRY, EXPORT.EFFECTS, EXPORT.COLORS,
                         EXPORT.METRICS, EXPORT.ANIMATION]:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())

    def replace(self, relative, before, after):
        path = self.root / relative
        source = path.read_text()
        self.assertEqual(source.count(before), 1)
        path.write_text(source.replace(before, after))

    def svg(self):
        return EXPORT.render_svg(EXPORT.read_mark(self.root))

    def copy_shadow_artifacts(self):
        for relative in [EXPORT.SHADOW_PNG, EXPORT.SHADOW_METADATA, EXPORT.SHADOW_RENDERER]:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())

    def test_generated_art_is_reproducible_from_only_dart_inputs(self):
        first = self.svg()
        self.assertEqual(first, self.svg())
        shipped = ROOT / EXPORT.PURE_SVG
        self.assertEqual(first, shipped.read_text())
        metadata = json.loads(first.split("\n", 2)[2].split("\n-->\n", 1)[0])
        for relative, digest in metadata["sourceSha256"].items():
            self.assertEqual(digest, hashlib.sha256((self.root / relative).read_bytes()).hexdigest())

    def test_viewport_centers_visible_ink_without_recentering_the_shadow(self):
        svg = ET.fromstring(self.svg())
        self.assertEqual(svg.attrib["viewBox"], "0 0 765 473")
        path = svg.find(".//s:path", SVG_NS)
        self.assertEqual(len(svg.findall(".//s:path", SVG_NS)), 1)
        self.assertEqual(path.attrib["fill-rule"], "nonzero")
        self.assertNotIn("crispEdges", self.svg())
        points = []
        for polygon in path.attrib["d"].split("Z"):
            if not polygon.strip():
                continue
            vertices = [(float(x), float(y)) for x, y in re.findall(
                r"[ML](-?[\d.]+) (-?[\d.]+)", polygon
            )]
            points.extend(vertices)
            area = sum(a[0] * b[1] - b[0] * a[1]
                       for a, b in zip(vertices, vertices[1:] + vertices[:1]))
            self.assertGreater(area, 0, "Every subpath must contribute the same winding")
        left, top = min(x for x, _ in points), min(y for _, y in points)
        right, bottom = max(x for x, _ in points), max(y for _, y in points)
        self.assertEqual((left, top, right, bottom), (30, 50, 735, 423))
        self.assertEqual(((left + right) / 2, (top + bottom) / 2), (765 / 2, 473 / 2))
        clip = svg.find(".//s:filter", SVG_NS)
        self.assertEqual(tuple(clip.attrib[key] for key in ["x", "y", "width", "height"]),
                         ("0", "30", "765", "433"))

    def test_numeric_effect_changes_are_derived_instead_of_retyped(self):
        self.replace(EXPORT.EFFECTS, "[0.346154, 1]", "[0.4, 1]")
        self.replace(EXPORT.EFFECTS, "_bottomOpacity = 0.3", "_bottomOpacity = 0.25")
        self.replace(EXPORT.EFFECTS, "sigma: 15, opacity: 0.06", "sigma: 16, opacity: 0.07")
        self.replace(EXPORT.EFFECTS, "logoBounds.bottom + 40 * scale", "logoBounds.bottom + 42 * scale")
        self.replace(EXPORT.COLORS, "meshMain = Color(0xFF001AFF)", "meshMain = Color(0xFF123456)")
        svg = ET.fromstring(self.svg())
        stops = svg.findall(".//s:stop", SVG_NS)
        self.assertEqual(stops[0].attrib["offset"], "0.4")
        self.assertEqual(stops[1].attrib["stop-opacity"], "0.25")
        self.assertTrue(all(stop.attrib["stop-color"] == "#123456" for stop in stops))
        blurs = svg.findall(".//s:feGaussianBlur", SVG_NS)
        self.assertEqual(blurs[1].attrib["stdDeviation"], "16")
        shadow = next(node for node in svg.findall(".//s:feColorMatrix", SVG_NS)
                      if node.attrib.get("result") == "shadow1")
        self.assertEqual(shadow.attrib["values"].split()[18], "0.07")
        self.assertEqual(svg.find(".//s:filter", SVG_NS).attrib["height"], "435")

    def test_numeric_geometry_changes_reach_the_single_painted_path(self):
        self.replace(EXPORT.GEOMETRY, "705, 206.944)", "705, 210)")
        path = ET.fromstring(self.svg()).find(".//s:path", SVG_NS)
        self.assertIn("L735 260L30 260Z", path.attrib["d"])

    def test_unsupported_compositing_change_is_rejected(self):
        self.replace(EXPORT.EFFECTS, "..blendMode = BlendMode.dstOut", "..blendMode = BlendMode.srcOut")
        with self.assertRaisesRegex(EXPORT.ExportError, "effect compositor"):
            self.svg()

    def test_unsupported_geometry_change_is_rejected(self):
        self.replace(EXPORT.GEOMETRY, "PathOperation.union", "PathOperation.intersect")
        with self.assertRaisesRegex(EXPORT.ExportError, "logo geometry"):
            self.svg()

    def test_unsupported_positioning_change_is_rejected(self):
        self.replace(EXPORT.ANIMATION, "..translate(size.width / 2, size.height / 2)",
                     "..translate(size.width / 2, size.height / 3)")
        with self.assertRaisesRegex(EXPORT.ExportError, "opening-logo placement"):
            self.svg()

    def test_a_different_color_binding_cannot_silently_export_the_old_color(self):
        self.replace(EXPORT.ANIMATION, "final foregroundColor = context.appColors.brandArtMain;",
                     "final foregroundColor = context.colorScheme.primary;")
        with self.assertRaisesRegex(EXPORT.ExportError, "brand color selection"):
            self.svg()

    def test_filter_overflow_requires_review_of_native_viewport_policy(self):
        self.replace(EXPORT.EFFECTS, "logoBounds.bottom + 40 * scale", "logoBounds.bottom + 60 * scale")
        with self.assertRaisesRegex(EXPORT.ExportError, "Native viewport"):
            self.svg()

    def test_check_mode_reports_stale_art_without_overwriting_it(self):
        self.copy_shadow_artifacts()
        imageset = self.root / EXPORT.IMAGESET
        imageset.mkdir(parents=True)
        (imageset / "splash_logo.svg").write_text("user-change")
        (imageset / "Contents.json").write_text(EXPORT.render_contents())
        with patch.object(EXPORT, "ROOT", self.root):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(EXPORT.main(["--check"]), 1)
        self.assertEqual((imageset / "splash_logo.svg").read_text(), "user-change")

    def test_native_svg_preserves_vector_ink_and_embeds_only_verified_shadows(self):
        self.copy_shadow_artifacts()
        mark = EXPORT.read_mark(self.root)
        shadow = EXPORT.read_shadow(self.root, mark)
        native = EXPORT.render_native_svg(mark, shadow)
        self.assertEqual(native, (ROOT / EXPORT.IMAGESET / "splash_logo.svg").read_text())
        svg = ET.fromstring(native)
        self.assertEqual(svg.findall(".//s:filter", SVG_NS), [])
        self.assertEqual(svg.findall(".//s:feGaussianBlur", SVG_NS), [])
        group = svg.find("s:g", SVG_NS)
        self.assertEqual([child.tag.split("}")[-1] for child in group], ["image", "path"])
        image = group.find("s:image", SVG_NS)
        embedded = image.attrib["{http://www.w3.org/1999/xlink}href"]
        self.assertTrue(embedded.startswith("data:image/png;base64,"))
        self.assertEqual(base64.b64decode(embedded.split(",", 1)[1]), shadow.png)
        pure_path = ET.fromstring(self.svg()).find(".//s:path", SVG_NS)
        native_path = group.find("s:path", SVG_NS)
        self.assertEqual(native_path.attrib["d"], pure_path.attrib["d"])
        self.assertEqual(native_path.attrib["fill-rule"], pure_path.attrib["fill-rule"])
        self.assertEqual(native_path.attrib["fill"], "#001AFF")
        self.assertEqual(native_path.attrib["mask"], "url(#aster-opening-alpha)")
        self.assertNotIn("mask", image.attrib)
        stops = svg.findall(".//s:stop", SVG_NS)
        self.assertEqual([stop.attrib["stop-color"] for stop in stops], ["#FFFFFF", "#FFFFFF"])
        self.assertEqual([stop.attrib["offset"] for stop in stops], ["0.346154", "1"])
        self.assertEqual([stop.attrib["stop-opacity"] for stop in stops], ["1", "0.3"])

    def test_native_shadow_rejects_changed_painter_constants(self):
        self.copy_shadow_artifacts()
        self.replace(EXPORT.EFFECTS, "[0.346154, 1]", "[0.4, 1]")
        with self.assertRaisesRegex(EXPORT.ExportError, "sourceSha256"):
            EXPORT.read_shadow(self.root, EXPORT.read_mark(self.root))

    def test_native_shadow_rejects_changed_renderer(self):
        self.copy_shadow_artifacts()
        renderer = self.root / EXPORT.SHADOW_RENDERER
        renderer.write_text(renderer.read_text() + "\n// altered renderer\n")
        with self.assertRaisesRegex(EXPORT.ExportError, "rendererToolSha256"):
            EXPORT.read_shadow(self.root, EXPORT.read_mark(self.root))

    def test_native_shadow_rejects_changed_png(self):
        self.copy_shadow_artifacts()
        png = self.root / EXPORT.SHADOW_PNG
        data = bytearray(png.read_bytes())
        data[-1] ^= 1
        png.write_bytes(data)
        with self.assertRaisesRegex(EXPORT.ExportError, "pngSha256"):
            EXPORT.read_shadow(self.root, EXPORT.read_mark(self.root))


if __name__ == "__main__":
    unittest.main()
