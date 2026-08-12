# Production Asset Manifest

Only assets declared explicitly in `pubspec.yaml` enter the Flutter bundle.
Every replacement must preserve the semantic role, update this manifest, and
pass visual and platform-build review.

| File | Role | Provenance and use terms | SHA-256 |
| --- | --- | --- | --- |
| `brand/utexo-mark.svg` | UTEXO product mark | Repository-supplied product artwork. Creator, assignment, and release clearance are not evidenced in this repository; see `ASSET-002`. | `75048dbe84db8665b7fb6b3e70f762e38f322f98abd08fce0bc4c9732423e15c` |
| `icons/tokens/btc.svg` | Bitcoin asset mark | Bitcoin Design visual-language download, <https://bitcoin.design/assets/images/guide/getting-started/visual-language/bitcoin-symbol.svg>. The guide records the derivative-work public-domain request and canonical `#F7931A` treatment. | `db7abfbe333989203822e602542703dd40680e130c9f58eff87b9954e1f40495` |
| `icons/tokens/usdt.svg` | Tether USDt asset mark | Official Tether circular-display SVG, <https://tether.to/images/logoCircle.svg>, normalized from CSS classes to equivalent explicit fills for deterministic `flutter_svg` rendering. Geometry and colors are unchanged. Use is subject to <https://tether.to/en/media/>; the mark must identify Tether tokens truthfully and remain undistorted. | `e4fabcb08c342981a9808d9431d2b2ccd37003d297610c7d3bf5194be4fbdc5e` |
| `texture/noise.jpg` | Subtle mesh noise | Repository-supplied authored texture, downsampled from 5554x3703 to 1600x1066 at JPEG quality 82. Original ownership and clearance are not evidenced; see `ASSET-002`. | `9aab1b0168217d180e9edd83c15615d61d59ea311a4ebb876aa399f3a905c02f` |
| `texture/shape.png` | Market-tile decoration | Repository-supplied authored texture, downsampled from 1500x1500 to 600x600. Original ownership and clearance are not evidenced; see `ASSET-002`. | `e6ed71e4630f15414ce5d6cccd48be12121543018c1f77d4fc30cbbd229fc804` |
| `data/countries.json` | Region catalog | Repository-supplied curated catalog: 249 unique ISO-like two-letter entries. Source ownership and update policy are not evidenced; see `ASSET-002`. | `40fd807353685a6f236659a761e41e59281a6e2b5a1b4fde77b1ebdd68f3e54b` |
| `data/currencies.json` | Fiat currency catalog | Repository-supplied curated catalog: 94 entries with intentional shared currency codes normalized by repository tests. Source ownership and update policy are not evidenced; see `ASSET-002`. | `89124c28e8347f2026021e1dac1f53418686d1dacd825df4351455827afbc727` |

The BIP39 word list and bundled font files have their own pinned source and
checksum records in `data/README.md` and `fonts/README.md`.

Native copies of the UTEXO mark and launch gradient are derivative packaging
of the same repository-supplied artwork. Android vector paths and iOS asset
catalog resources must remain visually equivalent to the Flutter assets.
