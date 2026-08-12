# Data Asset Provenance

## BIP39 English Word List

- File: `bip39_english.txt`
- Source: Bitcoin BIPs `bip-0039/english.txt`
- Source repository: <https://github.com/bitcoin/bips>
- Source commit: `ed4ffcb6a48d4dc4fdfc11cdba783c233db8c66e`
- SHA-256: `2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda`
- Entries: 2,048 lowercase English words in canonical order

The app uses this file only for immediate per-word input feedback. The pinned
`rgb_sdk_flutter` API remains authoritative for full BIP39 checksum validation.

## Region And Currency Catalogs

`countries.json` and `currencies.json` are repository-supplied curated product
catalogs. Their structural invariants and intentional shared-currency
normalization are covered by repository tests. Their original source,
ownership, and release clearance are not evidenced in this repository and
remain blocked under `ASSET-002`; engineering must not invent that provenance.
