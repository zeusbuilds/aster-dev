# Hosted Dev BUSDT wallet profile

The dedicated Debug profile uses Aster’s RGB_L1 wallet on UTEXO’s custom
Bitcoin Signet. It requires the `com.aster.devbridge.debug` application ID
and uses separate wallet metadata, native databases and credential namespaces.
Public Signet and production RGB_L1 retain their existing admission policies.

## Verified configuration

| Input | Value |
| --- | --- |
| Bitcoin block-one checkpoint | `0000001b808e4ece11c0cd922eaf9eee8d7dfba7e23e90b4f9614248daaf72cb` |
| Dev Esplora | `https://dev.esplora-01.mint.utexo.com` |
| Dev RGB proxy | `rpcs://dev.rgb-proxy.utexo.com/json-rpc`, protocol 1.0 |
| Arbitrum One RPC | `https://arb1.arbitrum.io/rpc`, chain `42161` |
| Mint lock limits | 2–7,200 Arbitrum blocks, matching the Iris Dev candidate |
| Bridge proxy | `0x6372ee2f86c3a551290635736b25855124932eed` |
| Backing USDT0 token | `0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9` |
| RGB asset | `rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE` |
| Native metadata | BFA, Bridged USDT, BUSDT, six decimals |
| Issuer export SHA-256 | `9307e39016e6373bd0ee1ea9fa5d6a4130120513d48da9268777893e150344e9` |
| Canonical wallet contract SHA-256 | `60a1b4f0d79706a7a51c6388fa14b951e119bae1ceffd811f4ebc62249817c4c` |
| Wallet native engine | BFA.7 `9ec49c08be2e68f08521281e3efbd760ec989cb9` with Flutter’s published native overlay |

The issuer supplied a 691-byte export. The WDK qualification extracted the
648-byte wallet genesis contract and confirmed that its asset ID and native
metadata matched the issuer export. Aster pins those canonical bytes and
verifies native metadata during wallet activation. Registration credits zero
funds. The previous BFA.5 contract remains historical.

Sources include the [issuer confirmation](https://utexo.slack.com/archives/C0A6286169J/p1794208420561419),
the [WDK candidate](https://github.com/UTEXO-Protocol/wdk-wallet-rgb/pull/23)
and the Iris Dev candidate identified in the [readiness record](DEV_SIGNET_READINESS.md).

## Browser bridge qualification

Iris uses `https://dev.mint.utexo.com`, WalletConnect project ID
`f8087f367176ba407873e1c9e33051d7`, and WebRGB chain `rgb:utexo`. The deployed
frontend requires `rgb_blindReceive` and Iris requires a confirmed usable RGB
output before approving a session with that capability. Aster’s ordinary
on-chain Receive screen continues to create witness invoices.

The Aster profile qualifies wallet access, registration and ordinary on-chain
operations. It does not advertise a browser connection. Completing that flow
requires a wallet-owned session transport with explicit consent and scope
checks, a request-bound durable blind invoice, and durable V1 burn and proof
recovery. The current Flutter SDK native journal covers BTC and RGB sends.
The optional Flutter WebRGB router does not negotiate or persist WalletConnect
sessions. It cannot establish the outcome of a native burn that lost its
response before the durable result was recorded.

Live bridge qualification also needs access to the hosted frontend and an
authorized disposable wallet with confirmed Dev Signet BTC, plus team-owned
Arbitrum USDT0 and gas for mint and payout testing. The hosted frontend returned
HTTP 403 during this qualification. Read-only RPC checks found a live
Arbitrum One backing pool. The bridge’s
[recorded end-to-end run](https://github.com/UTEXO-Protocol/bridge/actions/runs/42261217049)
stopped before broadcast, so it does not establish mint, burn or payout.
