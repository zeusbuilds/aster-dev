# Production Asset Manifest

Only assets declared explicitly in `pubspec.yaml` enter the Flutter bundle.
Every replacement must preserve the semantic role, update this manifest, and
pass visual and platform-build review.

| File | Role | Provenance and use terms | SHA-256 |
| --- | --- | --- | --- |
| `brand/aster-mark.svg` | Aster product mark | User-supplied white `logo.svg` revision received on 2026-10-26; replaces the previous product mark. Existing artwork provenance record: `ASSET-002`. | `936ac7f9191ade2877ea3ceff899e1b0f5b006d3a749cb7e8664b2fc3ff8a517` |
| `brand/aster-launch-opening.svg` | Generated vector master for the native opening treatment; excluded from the Flutter runtime bundle | Generated directly from the unchanged Flutter geometry/effect sources by `tool/export_aster_launch_logo.py`; no Figma or existing SVG is used as artwork input. iOS rendering uses the separately documented compatibility SVG; Android uses its own density PNGs rendered from the same Flutter painter. | `2cfca830863a632b7c63d079991ef7d5c057817b00ffe31fa14bfcd714450cbb` |
| `icons/tokens/btc.svg` | Bitcoin asset mark | Bitcoin Design visual-language download, <https://bitcoin.design/assets/images/guide/getting-started/visual-language/bitcoin-symbol.svg>. The guide records the derivative-work public-domain request and canonical `#F7931A` treatment. | `db7abfbe333989203822e602542703dd40680e130c9f58eff87b9954e1f40495` |
| `icons/tokens/usdt.svg` | Tether USDt asset mark | Official Tether circular-display SVG, <https://tether.to/images/logoCircle.svg>, normalized from CSS classes to equivalent explicit fills for deterministic `flutter_svg` rendering. Geometry and colors are unchanged. Use is subject to <https://tether.to/en/media/>; the mark must identify Tether tokens truthfully and remain undistorted. | `e4fabcb08c342981a9808d9431d2b2ccd37003d297610c7d3bf5194be4fbdc5e` |
| `texture/noise.jpg` | Subtle mesh noise | Repository-supplied authored texture, downsampled from 5554x3703 to 1600x1066 at JPEG quality 82. Original ownership and clearance are not evidenced; see `ASSET-002`. | `9aab1b0168217d180e9edd83c15615d61d59ea311a4ebb876aa399f3a905c02f` |
| `texture/shape.png` | Market-tile decoration | Repository-supplied authored texture, downsampled from 1500x1500 to 600x600. Original ownership and clearance are not evidenced; see `ASSET-002`. | `e6ed71e4630f15414ce5d6cccd48be12121543018c1f77d4fc30cbbd229fc804` |
| `data/countries.json` | Region catalog | Repository-supplied curated catalog: 249 unique ISO-like two-letter entries. Source ownership and update policy are not evidenced; see `ASSET-002`. | `40fd807353685a6f236659a761e41e59281a6e2b5a1b4fde77b1ebdd68f3e54b` |
| `data/currencies.json` | Fiat currency catalog | Repository-supplied curated catalog: 94 entries with intentional shared currency codes normalized by repository tests. Source ownership and update policy are not evidenced; see `ASSET-002`. | `89124c28e8347f2026021e1dac1f53418686d1dacd825df4351455827afbc727` |

The fiat catalog intentionally maps USD to US and EC, XPF to NC and PF, and
EUR to the EU pseudo-region used by `circle_flags`. Runtime selection is keyed
by the unique currency code and keeps the first curated presentation entry.
Settings exposes the reviewed 43-code intersection supported by the app's
typed market contract; unsupported catalog entries remain asset provenance,
not selectable dead options. The associated region catalog remains 249 unique
two-letter entries.

The BIP39 word list and bundled font files have their own pinned source and
checksum records in `data/README.md` and `fonts/README.md`.

The Flutter mark, animated geometry and native privacy covers preserve the same
revised artwork proportions. Every static loading, lock and privacy cover uses
white with the gradient blue mark and outside shadows. Startup holds that same
frame, then makes the logo opaque blue and removes its shadows before the blue
reveal; its background stays white. The iOS native launch asset is generated from
that unchanged Flutter opening treatment. iOS Icon Composer artwork remains user-managed. Android native splash uses
separate Flutter-rendered density resources. Privacy covers render independently
of those resources and share one appearance without a launch-phase bridge. See
`docs/BRAND_LOGO_INVENTORY.json` for current consumers and launch-effect values.

The pure vector opening master uses a balanced 765×473 transparent viewport with
the 705×373 mark centered inside it. The native image view uses root-view center
constraints and measures 173.617021276596×107.347517730496 points, giving a 160-point
visible mark with zero centering offset. The native `splash_logo.svg` retains the
same vector silhouette and gradient opacity, embedding only the actual Flutter-rendered
black-alpha shadow because CoreSVG omits the SVG filters in compiled assets. A
solid source-blue fill with a white alpha-gradient mask avoids CoreSVG's color-gradient
hue drift without changing or compensating the color. It is a hybrid SVG; the
vector master remains available separately. Source, renderer
and PNG hashes prevent stale effects from being reused. Reproduction commands
and raster details are in `tool/launch_artwork/README.md`. Neither generated
master nor shadow PNG is added to the Flutter runtime asset declarations.

Android launcher icons use the user-supplied `easyappicon-icons-1793097303787`
export received on 2026-10-27. Its density PNGs, adaptive definitions and white
background color are copied unchanged into `android/app/src/main/res/`, with
separate regular and round manifest references. The inventory records each
exported resource checksum. Store artwork is not packaged as an app resource.
Those Android launcher changes do not alter Android native splash or iOS assets.

Android native launch artwork is rendered directly by the unchanged Flutter
painter into dedicated transparent 288dp square PNGs at mdpi through xxxhdpi.
The visible mark stays 160dp wide and centred independently of its shadows;
all ink and shadow pixels fit inside the Android 12+ 192dp safe circle. The
legacy launch background centres the same bitmap. Both light and dark launch
themes are white; Android 13+ prefers showing the icon on every native splash.
No launcher icon, authentication cover or Flutter animation is changed by this
export. The renderer, provenance receipt and reproduction commands are recorded
in `tool/launch_artwork/README.md`. These PNGs are Android resources only, not
Flutter runtime assets.
