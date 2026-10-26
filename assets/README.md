# Production Asset Manifest

Only assets declared explicitly in `pubspec.yaml` enter the Flutter bundle.
Every replacement must preserve the semantic role, update this manifest, and
pass visual and platform-build review.

| File | Role | Provenance and use terms | SHA-256 |
| --- | --- | --- | --- |
| `brand/aster-mark.svg` | Aster product mark | User-supplied white `logo.svg` revision received on 2026-10-26; replaces the previous product mark. Existing artwork provenance record: `ASSET-002`. | `936ac7f9191ade2877ea3ceff899e1b0f5b006d3a749cb7e8664b2fc3ff8a517` |
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

The current Flutter mark, animated geometry, launcher icons and native privacy
covers use the same revised artwork and preserve its proportions. Native launch
artwork is reserved for the user's separate splash update and deliberately
retains the previous mark. Privacy and launcher resources are separate from
those native splash resources. See `docs/BRAND_LOGO_INVENTORY.json` at the
repository root for every current consumer and the explicit splash exceptions.
