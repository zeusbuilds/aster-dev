#!/usr/bin/env python3
"""Export the unchanged Flutter opening mark as an iOS launch SVG.

This deliberately supports one audited Dart painter, not arbitrary Dart. Numeric
artwork constants are parsed from their source declarations. Structural hashes
reject changes to geometry/compositing algorithms until the exporter is reviewed.
No SVG or Figma asset is an input. Run with --check to detect stale generated art.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parents[1]
GEOMETRY = "lib/shared/branding/aster_logo_geometry.dart"
EFFECTS = "lib/shared/branding/aster_launch_logo.dart"
COLORS = "lib/shared/theme/tokens/color_tokens.dart"
METRICS = "lib/shared/theme/tokens/component_metrics_tokens.dart"
ANIMATION = "lib/shared/screens/animated_splash_screen.dart"
IMAGESET = "ios/Runner/Assets.xcassets/splash_logo.imageset"
PURE_SVG = "assets/brand/aster-launch-opening.svg"
SHADOW_PNG = "tool/launch_artwork/aster-launch-opening-shadow.png"
SHADOW_METADATA = "tool/launch_artwork/aster-launch-opening-shadow.json"
SHADOW_RENDERER = "tool/render_aster_launch_shadow_test.dart"
SHADOW_RASTER_SCALE = 3
NUMBER = r"-?(?:\d+(?:\.\d*)?|\.\d+)"

# The existing native artboard uses balanced 50-unit vertical margins. This is
# transparent viewport space, not a change to Flutter's shape or filter clip.
VERTICAL_CANVAS_MARGIN = Decimal(50)

# Populated from the reviewed, unchanged Dart implementations. Only declarations
# parsed below are redacted; any unsupported algorithm change fails closed.
GEOMETRY_STRUCTURE_SHA256 = "4dd829b64994152d435a76fcf3b3e042bde35e6a5e4d92d5b991678f3e1e2f1e"
EFFECTS_STRUCTURE_SHA256 = "8b188c9267f5a91e9e73a93948895306e01fdd86d9fbab8decae9b8b8b9240c5"
PAINTER_STRUCTURE_SHA256 = "95760edd3539bafc203c565ff954d46bd8cd7066fc1dddc589d27159504c3c2e"


class ExportError(ValueError):
    """An input no longer has the explicitly supported painter contract."""


def _plain(source: str) -> str:
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)


def _one(pattern: str, source: str, name: str) -> re.Match[str]:
    matches = list(re.finditer(pattern, source, flags=re.S))
    if len(matches) != 1:
        raise ExportError(f"Expected exactly one supported {name}; found {len(matches)}")
    return matches[0]


def _numbers(text: str) -> tuple[Decimal, ...]:
    # A declaration may contain only comma-delimited numeric literals.
    if re.sub(NUMBER, "", text).replace(",", "").strip():
        raise ExportError(f"Unsupported numeric expression: {text!r}")
    values = tuple(Decimal(value) for value in re.findall(NUMBER, text))
    if not values or not all(value.is_finite() for value in values):
        raise ExportError("Expected finite numeric constants")
    return values


def _digest(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def _structure(source: str, declarations: list[str]) -> str:
    for pattern in declarations:
        match = _one(pattern, source, "source declaration")
        source = source[: match.start()] + "PARSED_DECLARATION;" + source[match.end() :]
    return _digest(re.sub(r"\s+", "", source))


def _require_structure(actual: str, expected: str, name: str) -> None:
    if actual != expected:
        raise ExportError(
            f"Unsupported {name} implementation ({actual}). Review the exporter "
            "against the Dart implementation before updating its structural fingerprint."
        )


def _declaration(name: str, expression: str) -> str:
    return rf"static\s+const\s+{re.escape(name)}\s*=\s*{expression}\s*;"


GEOMETRY_DECLARATIONS = [
    _declaration("size", r"Size\((?P<values>[^)]*)\)"),
    _declaration("horizontal", r"Rect\.fromLTRB\((?P<values>[^)]*)\)"),
    _declaration("_descending", r"<Offset>\[(?P<values>.*?)\]"),
    _declaration("_ascending", r"<Offset>\[(?P<values>.*?)\]"),
]
EFFECT_DECLARATIONS = [
    _declaration("_sourceWidth", rf"(?P<values>{NUMBER})"),
    _declaration("_gradientStops", r"<double>\[(?P<values>.*?)\]"),
    _declaration("_bottomOpacity", rf"(?P<values>{NUMBER})"),
    _declaration("_shadows", r"<_LaunchShadow>\[(?P<values>.*?)\]"),
    _declaration("_hardAlpha", r"ColorFilter\.matrix\(<double>\[(?P<values>.*?)\]\)"),
    r"final\s+filterBounds\s*=\s*Rect\.fromLTRB\((?P<values>.*?)\)\s*;",
]


def _values(pattern: str, source: str, name: str) -> str:
    return _one(pattern, source, name).group("values")


def _polygon(text: str) -> tuple[tuple[Decimal, Decimal], ...]:
    pattern = rf"Offset\(\s*({NUMBER})\s*,\s*({NUMBER})\s*\)"
    points = tuple((Decimal(x), Decimal(y)) for x, y in re.findall(pattern, text))
    if re.sub(pattern, "", text).replace(",", "").strip() or len(points) != 4:
        raise ExportError("Expected four literal vertices for each diagonal")
    twice_area = sum(
        a[0] * b[1] - b[0] * a[1]
        for a, b in zip(points, points[1:] + points[:1])
    )
    if twice_area == 0:
        raise ExportError("A logo polygon has no area")
    return points if twice_area > 0 else tuple(reversed(points))


def _painter_body(animation: str) -> str:
    return _one(
        r"class\s+_LogoPainter\s+extends\s+CustomPainter\s*\{.*?"
        r"@override\s+void\s+paint\(Canvas\s+canvas,\s*Size\s+size\)\s*"
        r"(?P<body>\{.*?\})\s*@override\s+bool\s+shouldRepaint",
        animation,
        "opening-logo painter",
    ).group("body")


@dataclass(frozen=True)
class OpeningMark:
    width: Decimal
    height: Decimal
    polygons: tuple[tuple[tuple[Decimal, Decimal], ...], ...]
    stops: tuple[Decimal, ...]
    bottom_alpha: Decimal
    blue: str
    hard_alpha: tuple[Decimal, ...]
    shadows: tuple[tuple[Decimal, Decimal, Decimal, Decimal], ...]
    padding: tuple[Decimal, Decimal, Decimal, Decimal]
    visible_width: Decimal
    source_hashes: dict[str, str]


def read_mark(root: Path) -> OpeningMark:
    paths = [GEOMETRY, EFFECTS, COLORS, METRICS, ANIMATION]
    originals = {path: (root / path).read_text(encoding="utf-8") for path in paths}
    sources = {path: _plain(source) for path, source in originals.items()}
    geometry, effects = sources[GEOMETRY], sources[EFFECTS]
    _require_structure(
        _structure(geometry, GEOMETRY_DECLARATIONS),
        GEOMETRY_STRUCTURE_SHA256,
        "logo geometry",
    )
    _require_structure(
        _structure(effects, EFFECT_DECLARATIONS),
        EFFECTS_STRUCTURE_SHA256,
        "logo effect compositor",
    )
    _require_structure(
        _digest(re.sub(r"\s+", "", _painter_body(sources[ANIMATION]))),
        PAINTER_STRUCTURE_SHA256,
        "opening-logo placement",
    )
    width, height = _numbers(_values(GEOMETRY_DECLARATIONS[0], geometry, "mark size"))
    left, top, right, bottom = _numbers(
        _values(GEOMETRY_DECLARATIONS[1], geometry, "horizontal stroke")
    )
    if not (width > 0 and height > 0 and 0 <= left < right <= width
            and 0 <= top < bottom <= height and left == 0 and right == width):
        raise ExportError("Unsupported mark size or horizontal stroke bounds")
    polygons = (
        ((left, top), (right, top), (right, bottom), (left, bottom)),
        _polygon(_values(GEOMETRY_DECLARATIONS[2], geometry, "descending diagonal")),
        _polygon(_values(GEOMETRY_DECLARATIONS[3], geometry, "ascending diagonal")),
    )
    if any(not (0 <= x <= width and 0 <= y <= height)
           for polygon in polygons for x, y in polygon):
        raise ExportError("A logo vertex lies outside the declared artwork")
    if Decimal(_values(EFFECT_DECLARATIONS[0], effects, "effect scale")) != width:
        raise ExportError("Painter and geometry source widths disagree")
    stops = _numbers(_values(EFFECT_DECLARATIONS[1], effects, "gradient stops"))
    bottom_alpha = Decimal(_values(EFFECT_DECLARATIONS[2], effects, "bottom opacity"))
    if len(stops) != 2 or not (0 <= stops[0] < stops[1] == 1 and 0 <= bottom_alpha <= 1):
        raise ExportError("Unsupported opening gradient")
    hard_alpha = _numbers(_values(EFFECT_DECLARATIONS[4], effects, "hard-alpha matrix"))
    if len(hard_alpha) != 20 or hard_alpha[18] <= 0 or any(
        value != 0 for index, value in enumerate(hard_alpha) if index != 18
    ):
        raise ExportError("Expected a black alpha-only hard-source mask")
    shadow_text = _values(EFFECT_DECLARATIONS[3], effects, "shadow list")
    shadow_pattern = (
        rf"_LaunchShadow\(\s*offset:\s*Offset\(\s*({NUMBER})\s*,\s*({NUMBER})\s*\),"
        rf"\s*sigma:\s*({NUMBER})\s*,\s*opacity:\s*({NUMBER})\s*\)"
    )
    shadows = tuple(tuple(Decimal(value) for value in item)
                    for item in re.findall(shadow_pattern, shadow_text))
    if not shadows or re.sub(shadow_pattern, "", shadow_text).replace(",", "").strip():
        raise ExportError("Unsupported shadow declaration")
    if any(sigma <= 0 or not 0 <= alpha <= 1 for _, _, sigma, alpha in shadows):
        raise ExportError("Unsupported shadow blur or opacity")
    padding_text = _values(EFFECT_DECLARATIONS[5], effects, "shadow clipping bounds")
    padding_pattern = (
        rf"\s*logoBounds\.left\s*-\s*({NUMBER})\s*\*\s*scale\s*,"
        rf"\s*logoBounds\.top\s*-\s*({NUMBER})\s*\*\s*scale\s*,"
        rf"\s*logoBounds\.right\s*\+\s*({NUMBER})\s*\*\s*scale\s*,"
        rf"\s*logoBounds\.bottom\s*\+\s*({NUMBER})\s*\*\s*scale\s*,?\s*"
    )
    padding_match = re.fullmatch(padding_pattern, padding_text)
    if padding_match is None:
        raise ExportError("Unsupported shadow clip expression")
    padding = tuple(Decimal(value) for value in padding_match.groups())
    if min(padding) < 0 or padding[0] != padding[2] or max(padding[1], padding[3]) > VERTICAL_CANVAS_MARGIN:
        raise ExportError("Native viewport no longer contains a centered mark and its filter")
    color_role = _one(
        r"brandArtMain:\s*_AsterPalette\.(?P<name>\w+)\s*,",
        sources[COLORS],
        "brand-art color role",
    ).group("name")
    color = _one(
        rf"static\s+const\s+{re.escape(color_role)}\s*=\s*Color\(0x(?P<argb>[0-9A-Fa-f]{{8}})\)\s*;",
        sources[COLORS],
        "brand-art palette color",
    ).group("argb").upper()
    if color[:2] != "FF":
        raise ExportError("Expected an opaque base brand color")
    animation = sources[ANIMATION]
    for pattern, name in [
        (r"final\s+foregroundColor\s*=\s*context\.appColors\.brandArtMain\s*;", "brand color selection"),
        (r"painter:\s*_LogoPainter\(\s*color:\s*foregroundColor,", "logo color binding"),
        (r"logoWidth:\s*context\.metrics\.splashLogoWidth,", "logo width binding"),
    ]:
        # Other animation geometry may also reference the width token.
        if name == "logo width binding":
            if re.search(pattern, animation) is None:
                raise ExportError("Unsupported logo width binding")
        else:
            _one(pattern, animation, name)
    visible_width = Decimal(_one(
        rf"this\.splashLogoWidth\s*=\s*(?P<width>{NUMBER})\s*,",
        sources[METRICS],
        "visible splash width",
    ).group("width"))
    if visible_width <= 0:
        raise ExportError("Visible mark width must be positive")
    return OpeningMark(
        width, height, polygons, stops, bottom_alpha, "#" + color[2:], hard_alpha,
        shadows, padding, visible_width,
        {path: _digest(originals[path]) for path in paths},
    )


def _n(value: Decimal | int) -> str:
    value = Decimal(value)
    return "0" if value == 0 else format(value.normalize(), "f")


def render_svg(mark: OpeningMark) -> str:
    left, top, right, bottom = mark.padding
    x, y = left, VERTICAL_CANVAS_MARGIN
    canvas_width = mark.width + left + right
    canvas_height = mark.height + 2 * y
    metadata = {
        "generator": "tool/export_aster_launch_logo.py",
        "sourcePose": {"rotation": 0, "expansion": 0, "colorProgress": 0},
        "sourceSha256": mark.source_hashes,
        "nativeViewportPolicy": "Centered visible mark; balanced transparent vertical margins",
        "visibleMarkWidthLogicalPixels": _n(mark.visible_width),
        "nativeImageWidthLogicalPixels": _n(canvas_width * mark.visible_width / mark.width),
        "nativeImageHeightLogicalPixels": _n(canvas_height * mark.visible_width / mark.width),
    }
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<!-- Generated from Flutter Dart source. Do not edit; run tool/export_aster_launch_logo.py.",
        escape(json.dumps(metadata, indent=2, sort_keys=True)),
        "-->",
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{_n(canvas_width)}" height="{_n(canvas_height)}" viewBox="0 0 {_n(canvas_width)} {_n(canvas_height)}" fill="none">',
        '  <defs>',
        f'    <linearGradient id="aster-opening-fill" x1="{_n(x + mark.width / 2)}" y1="{_n(y)}" x2="{_n(x + mark.width / 2)}" y2="{_n(y + mark.height)}" gradientUnits="userSpaceOnUse">',
        f'      <stop offset="{_n(mark.stops[0])}" stop-color="{mark.blue}" stop-opacity="1"/>',
        f'      <stop offset="{_n(mark.stops[1])}" stop-color="{mark.blue}" stop-opacity="{_n(mark.bottom_alpha)}"/>',
        '    </linearGradient>',
        f'    <filter id="aster-opening-shadows" x="0" y="{_n(y - top)}" width="{_n(canvas_width)}" height="{_n(mark.height + top + bottom)}" filterUnits="userSpaceOnUse" primitiveUnits="userSpaceOnUse" color-interpolation-filters="sRGB">',
        '      <feFlood flood-opacity="0" result="transparent"/>',
        f'      <feColorMatrix in="SourceAlpha" type="matrix" values="{" ".join(_n(value) for value in mark.hard_alpha)}" result="hardAlpha"/>',
    ]
    previous = "transparent"
    for index, (dx, dy, sigma, opacity) in enumerate(mark.shadows):
        matrix = [Decimal(0)] * 20
        matrix[18] = opacity
        lines += [
            f'      <feOffset in="hardAlpha" dx="{_n(dx)}" dy="{_n(dy)}" result="offset{index}"/>',
            f'      <feGaussianBlur in="offset{index}" stdDeviation="{_n(sigma)}" result="blur{index}"/>',
            f'      <feComposite in="blur{index}" in2="hardAlpha" operator="out" result="outside{index}"/>',
            f'      <feColorMatrix in="outside{index}" type="matrix" values="{" ".join(_n(value) for value in matrix)}" result="shadow{index}"/>',
            f'      <feBlend in="shadow{index}" in2="{previous}" mode="normal" result="stack{index}"/>',
        ]
        previous = f"stack{index}"
    lines += [
        f'      <feBlend in="SourceGraphic" in2="{previous}" mode="normal"/>',
        '    </filter>',
        '  </defs>',
        '  <g filter="url(#aster-opening-shadows)">',
    ]
    subpaths = []
    for polygon in mark.polygons:
        vertices = [f"{_n(px + x)} {_n(py + y)}" for px, py in polygon]
        subpaths.append("M" + "L".join(vertices) + "Z")
    # All polygons have positive winding. Nonzero fills their union once, so
    # translucent overlapping strokes never receive multiple paint operations.
    lines += [
        f'    <path d="{" ".join(subpaths)}" fill="url(#aster-opening-fill)" fill-rule="nonzero"/>',
        '  </g>',
        '</svg>',
    ]
    return "\n".join(lines) + "\n"


def render_contents() -> str:
    return json.dumps({
        "images": [{"filename": "splash_logo.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "original",
        },
    }, indent=2) + "\n"


def _render_spec(mark: OpeningMark) -> dict[str, object]:
    left, _, right, _ = mark.padding
    width = mark.width + left + right
    height = mark.height + 2 * VERTICAL_CANVAS_MARGIN
    return {
        "schemaVersion": 1,
        "sourceSha256": mark.source_hashes,
        "viewportSourceUnits": [float(width), float(height)],
        "markSourceUnits": [float(mark.width), float(mark.height)],
        "markCenterSourceUnits": [float(left + mark.width / 2), float(height / 2)],
        "rasterScale": SHADOW_RASTER_SCALE,
        "blueArgb": "FF" + mark.blue[1:],
        "outputPng": SHADOW_PNG,
        "outputMetadata": SHADOW_METADATA,
    }


def _spec_bytes(mark: OpeningMark) -> bytes:
    return (json.dumps(_render_spec(mark), indent=2, sort_keys=True) + "\n").encode("utf-8")


def _render_shadow(root: Path, mark: OpeningMark, flutter: str | None) -> None:
    command = flutter or shutil.which("flutter")
    if command is None:
        local = root / ".fvm/flutter_sdk/bin/flutter"
        if local.exists():
            command = str(local)
    if command is None:
        raise ExportError("Pass --flutter /path/to/flutter when regenerating the shadow PNG")
    spec_path = root / ".buildlog/native-launch-export/shadow-render-spec.json"
    spec_path.parent.mkdir(parents=True, exist_ok=True)
    spec_path.write_bytes(_spec_bytes(mark))
    subprocess.run([
        command, "test", "--no-pub", "--concurrency=1",
        f"--dart-define=ASTER_LAUNCH_RENDER_SPEC={spec_path}", SHADOW_RENDERER,
    ], cwd=root, check=True)


@dataclass(frozen=True)
class ShadowRaster:
    png: bytes
    metadata: dict[str, object]


def read_shadow(root: Path, mark: OpeningMark) -> ShadowRaster:
    """Refuse stale renderer output rather than silently showing old effects."""
    try:
        png = (root / SHADOW_PNG).read_bytes()
        metadata = json.loads((root / SHADOW_METADATA).read_text(encoding="utf-8"))
    except OSError as error:
        raise ExportError("Generate native shadow art with --render-shadow --flutter /path/to/flutter") from error
    spec = _render_spec(mark)
    expected_pixels = [int(value * SHADOW_RASTER_SCALE) for value in spec["viewportSourceUnits"]]
    if (len(png) < 24 or png[:8] != b"\x89PNG\r\n\x1a\n"
            or list(struct.unpack(">II", png[16:24])) != expected_pixels):
        raise ExportError("Native shadow PNG has unsupported format or dimensions")
    checks = {
        "schemaVersion": 1,
        "rendererTool": SHADOW_RENDERER,
        "rendererToolSha256": hashlib.sha256((root / SHADOW_RENDERER).read_bytes()).hexdigest(),
        "sourceSha256": mark.source_hashes,
        "renderSpecSha256": hashlib.sha256(_spec_bytes(mark)).hexdigest(),
        "pngSha256": hashlib.sha256(png).hexdigest(),
        "viewportSourceUnits": spec["viewportSourceUnits"],
        "rasterScale": SHADOW_RASTER_SCALE,
        "pixelSize": expected_pixels,
        "colorSpace": "sRGB",
        "coloredPixels": 0,
        "forwardedShadowPaths": 4,
        "suppressedForegroundPaths": 1,
    }
    for key, expected in checks.items():
        if metadata.get(key) != expected:
            raise ExportError(f"Native shadow provenance is stale or invalid ({key}); regenerate with --render-shadow")
    if not (0 < metadata.get("maximumAlpha", 0) < 255 and metadata.get("nonTransparentPixels", 0) > 0):
        raise ExportError("Native shadow PNG must contain only translucent black shadow pixels")
    return ShadowRaster(png, metadata)


def render_native_svg(mark: OpeningMark, shadow: ShadowRaster) -> str:
    """Keep vector ink; avoid CoreSVG's filter and color-gradient limitations."""
    svg = render_svg(mark)
    svg, removed = re.subn(r'    <filter\b.*?</filter>\n', "", svg, flags=re.S)
    if removed != 1:
        raise ExportError("Expected exactly one pure-SVG shadow filter")
    svg = svg.replace(
        '<svg xmlns="http://www.w3.org/2000/svg"',
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"',
        1,
    )
    left, _, right, _ = mark.padding
    width = mark.width + left + right
    height = mark.height + 2 * VERTICAL_CANVAS_MARGIN
    # CoreSVG changes a blue color-gradient's RGB even where its alpha is one.
    # A solid blue fill renders correctly. The equivalent white-alpha gradient
    # mask varies only opacity, preserving the source RGB without compensation.
    opacity = (
        f'    <linearGradient id="aster-opening-opacity" x1="{_n(left + mark.width / 2)}" y1="{_n(VERTICAL_CANVAS_MARGIN)}" '
        f'x2="{_n(left + mark.width / 2)}" y2="{_n(VERTICAL_CANVAS_MARGIN + mark.height)}" gradientUnits="userSpaceOnUse">\n'
        f'      <stop offset="{_n(mark.stops[0])}" stop-color="#FFFFFF" stop-opacity="1"/>\n'
        f'      <stop offset="{_n(mark.stops[1])}" stop-color="#FFFFFF" stop-opacity="{_n(mark.bottom_alpha)}"/>\n'
        '    </linearGradient>\n'
        f'    <mask id="aster-opening-alpha" x="0" y="0" width="{_n(width)}" height="{_n(height)}" '
        'maskUnits="userSpaceOnUse" maskContentUnits="userSpaceOnUse" mask-type="alpha">\n'
        f'      <rect x="0" y="0" width="{_n(width)}" height="{_n(height)}" fill="url(#aster-opening-opacity)"/>\n'
        '    </mask>'
    )
    svg, replaced = re.subn(r'    <linearGradient\b.*?</linearGradient>', opacity, svg, flags=re.S)
    if replaced != 1:
        raise ExportError("Expected exactly one pure-SVG color gradient")
    svg = svg.replace(
        'fill="url(#aster-opening-fill)" fill-rule="nonzero"',
        f'fill="{mark.blue}" fill-rule="nonzero" mask="url(#aster-opening-alpha)"',
        1,
    )
    data = base64.b64encode(shadow.png).decode("ascii")
    image = (
        f'    <image x="0" y="0" width="{_n(width)}" height="{_n(height)}" '
        f'preserveAspectRatio="none" xlink:href="data:image/png;base64,{data}"/>\n'
    )
    svg = svg.replace('  <g filter="url(#aster-opening-shadows)">\n', '  <g>\n' + image, 1)
    comment = (
        '<!-- Native compatibility SVG: solid source-blue vector path with equivalent alpha-gradient mask and embedded actual-Flutter '
        'shadow PNG. CoreSVG omits SVG filters and shifts color-gradient RGB. Pure vector master: ' + PURE_SVG + '.\n'
        'Shadow PNG SHA-256: ' + str(shadow.metadata["pngSha256"]) + '\n'
        'Shadow raster: ' + str(shadow.metadata["pixelSize"]) + ', sRGB, '
        + str(SHADOW_RASTER_SCALE) + ' pixels per SVG source unit. -->\n'
    )
    return svg.replace('<svg ', comment + '<svg ', 1)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if generated native artwork is stale; do not write files")
    parser.add_argument("--render-shadow", action="store_true", help="Regenerate shadow-only PNG through the unchanged Flutter painter before exporting")
    parser.add_argument("--flutter", help="Flutter executable for --render-shadow (no application build or device is used)")
    args = parser.parse_args(argv)
    if args.check and args.render_shadow:
        parser.error("--check never writes artifacts; run --render-shadow separately")
    try:
        mark = read_mark(ROOT)
        if args.render_shadow:
            _render_shadow(ROOT, mark, args.flutter)
        shadow = read_shadow(ROOT, mark)
        outputs = {
            ROOT / PURE_SVG: render_svg(mark),
            ROOT / IMAGESET / "splash_logo.svg": render_native_svg(mark, shadow),
            ROOT / IMAGESET / "Contents.json": render_contents(),
        }
        stale = [str(path.relative_to(ROOT)) for path, value in outputs.items()
                 if not path.exists() or path.read_text(encoding="utf-8") != value]
        if args.check:
            if stale:
                raise ExportError("Generated native launch artwork is stale: " + ", ".join(stale))
            print("Pure master and native compatibility SVG match current Flutter sources and shadow-render provenance.")
            return 0
        for path, value in outputs.items():
            if path.exists() and path.read_text(encoding="utf-8") == value:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=path.parent, delete=False) as handle:
                handle.write(value)
                temporary = Path(handle.name)
            temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o644)
            temporary.replace(path)
        print(f"Exported {PURE_SVG} and native compatibility SVG from five Dart source files.")
        return 0
    except (ExportError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Launch SVG export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
