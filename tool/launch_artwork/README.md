# Native opening artwork generated from Flutter

The production animation and painter remain unchanged. The exporter reads the
current Dart geometry, color role, gradient, shadow mask and clipping constants;
it never reads a Figma or existing SVG as artwork input.

```sh
python3 tool/export_aster_launch_logo.py --render-shadow --flutter /path/to/flutter
python3 tool/export_aster_launch_logo.py --check
python3 test/tool/export_aster_launch_logo_test.py
```

The first command runs a host Flutter test renderer, without an application build
or device. Use it whenever an input source or renderer changes. Re-running the
exporter without `--render-shadow` reuses the checked raster only when all source,
renderer, render-spec and PNG hashes still match. `--check` writes nothing.

Outputs:

- `assets/brand/aster-launch-opening.svg`: genuine vector geometry, gradient and
  outside-only SVG filter effects, with source hashes and no crisp-edge flag.
- `ios/Runner/Assets.xcassets/splash_logo.imageset/splash_logo.svg`: native
  compatibility SVG, retaining the same vector silhouette and gradient opacity
  with the actual Flutter-rendered shadow embedded as a transparent PNG. CoreSVG
  omits SVG filters and changes the hue of color-gradient fills in compiled
  assets. A solid source-blue vector fill with a white alpha-gradient mask is
  mathematically equivalent and preserves the correct hue without compensating
  color values. This native file is deliberately hybrid.
- `aster-launch-opening-shadow.png` and `.json` in this directory: the captured
  black-alpha shadow and its source/renderer/spec provenance. Neither this PNG
  nor the vector master is added to the Flutter runtime asset bundle.

The renderer calls the actual `AsterLaunchLogo.paint` at opening progress zero.
Its Canvas proxy forwards all four paths inside the production shadow layers,
including hard-alpha masking and outside-only compositing. It suppresses only
the single final foreground path after the painter restores its initial save
count. An unsupported Canvas operation fails loudly. Raw output is checked for
nonzero translucent shadow alpha and zero colored pixels before PNG encoding.

The balanced source canvas is 765×473, with the unshadowed 705×373 mark centered
at (382.5,236.5). The effect clip remains (0,30,765,433). Shadows are rasterized in
sRGB at three pixels per source unit: **2295×1419**, an oversampled transparent
image. When the visible vector mark is 160 logical pixels wide, the entire image
occupies 173.617021276596×107.347517730496 logical pixels; the shadow scales with
that same viewport. Its high-resolution alpha is downsampled by native rendering,
while the logo itself stays vector. Small rasterization differences must be
verified against the compiled native asset at the target display scales.

Structural fingerprints fail closed when the supported geometry, compositor or
placement algorithm changes. Numeric constants are parsed instead of duplicated.
Review the exporter before changing those fingerprints; do not update them just
to silence a failed check. The JSON receipt records the Dart runtime and color
space used for the captured raster.

## Android native launch resources

```sh
python3 tool/export_android_launch_logo.py --render --flutter /path/to/flutter
python3 tool/export_android_launch_logo.py --check
python3 test/tool/export_android_launch_logo_test.py
```

Android uses a **separate native launch drawable**, `aster_launch_opening.png`,
rendered directly through the same unchanged Flutter geometry and
`AsterLaunchLogo.paint(colorProgress: 0)`. It does not reuse or change the Android
launcher icon. The host renderer runs with `flutter test --no-pub`, without an
application build, device, Docker or stack connection. It draws the whole mark
and both outside-only shadows together in sRGB; it does not approximate the
shadows in an Android VectorDrawable or resample one density into another.

The transparent canvas is **288×288 dp**, matching Android 12+'s splash-icon
viewport without an icon background. The unshadowed mark remains **160 dp wide**
and **84.6524822695 dp high**, centered at **(144,144)** independently of the
asymmetric shadows. Every nontransparent pixel, including the shadow, is checked
against the **192 dp safe circle**. Transparent padding is balanced around the
visible geometry, so a longer shadow below the mark cannot shift its center.

Generated resources:

| Density | Scale | PNG dimensions |
|---|---:|---:|
| `drawable-mdpi` | 1 | 288×288 |
| `drawable-hdpi` | 1.5 | 432×432 |
| `drawable-xhdpi` | 2 | 576×576 |
| `drawable-xxhdpi` | 3 | 864×864 |
| `drawable-xxxhdpi` | 4 | 1152×1152 |

`android-launch-opening.json` records all five source SHA-256 hashes, renderer
hash, render-spec hash, exact density paths/dimensions, each PNG hash, color space
and Dart runtime. `--check` verifies this receipt and independently decodes each
PNG using the Python standard library, checking chunk CRCs, density dimensions,
source-blue opaque ink, translucent fill, black outside shadows, transparent
edges and mask containment. The opaque-edge check allows one channel value for
Flutter's own antialiasing/compositing quantization. Unsupported painter algorithm
changes fail closed through the shared audited Dart parser. Missing, edited or
stale PNGs must be regenerated; `--check` writes nothing.

These PNGs are native Android resources only. Neither renderer nor receipt is
added to the Flutter asset bundle, and the production animated splash remains
unchanged. Android's OS launch timing, status/navigation bars and final native to
Flutter alignment still require verification on the running Android build.
