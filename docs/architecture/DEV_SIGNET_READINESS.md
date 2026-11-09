# Hosted Dev Signet readiness

The dedicated Aster Debug build uses the Dev wallet profile reviewed against
Iris `37003ffdf27b6c089327b98e92a1d97ca3e6ad71` and WDK
`2.1.0-alpha.14`. See the [build preset and instructions](../../config/README.md)
and the [deployment handoff](DEV_USDT_TEAM_INPUTS.md).

## Deployment identity

| Item | Value |
| --- | --- |
| Installed Aster test app | `com.aster.devbridge.debug` |
| Aster deployment | `signet` / `dev-signet` / `rgb-l1` |
| Bitcoin block 1 | `0000001b808e4ece11c0cd922eaf9eee8d7dfba7e23e90b4f9614248daaf72cb` |
| Dev Bitcoin Esplora | `https://dev.esplora-01.mint.utexo.com` |
| Dev RGB proxy | `rpcs://dev.rgb-proxy.utexo.com/json-rpc`, protocol 1.0 |
| Backing EVM | Arbitrum One, chain `42161`, `https://arb1.arbitrum.io/rpc` |
| Mint lock validation | 2–7,200 Arbitrum blocks, matching the Iris candidate |
| Current RGB asset | `rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE`, BFA, Bridged USDT / BUSDT, precision 6 |
| Contract export | Iris alpha.14 registry, CON V1, SHA-256 `60a1b4f0d79706a7a51c6388fa14b951e119bae1ceffd811f4ebc62249817c4c` |
| BFA.7 source | `9ec49c08be2e68f08521281e3efbd760ec989cb9` |

Public and Dev Signet share address encoding but have different block 1
hashes. Native Dev resolution verifies the checkpoint before online wallet
operations. The app pins the exact endpoints and checks the expected EVM chain
ID. It imports the current public genesis with its expected RGB asset ID and
verifies native BFA schema, name, ticker and precision before enabling the
asset. The historical BFA.5 export cannot substitute for it.

## Wallet scope

Aster validates the installed app identifier before reading the Dev wallet
registry or native storage and uses separate wallet-secret storage. Fresh Dev
profiles persist their deployment, and public Signet and unknown legacy
profiles cannot reopen on Dev. The normal wallet flow creates witness receive
requests. Dev Send uses the configured proxy and the selected BUSDT contract.
An assetless open-amount invoice can use that selected contract, while a fixed
amount without an asset is rejected. A valid native fee estimate takes
precedence. Only a typed missing estimate uses the Dev policy of 1 sat/vB.
Send labels that rate as a Dev Signet fee rate.

Hosted smoke tests on the iOS 27 simulator and Android 17 emulator opened
fresh wallets, verified the BUSDT metadata at zero balance, generated BTC and
witness BUSDT receive requests, and reopened the same wallet identities in
new processes. Both used the Dev fee fallback. Android passed on the 16 KiB
guest with the dedicated APK's cleartext traffic disabled. iOS reopen went
through the app lock with simulator Face ID. An earlier Android fixture that
predated the Dev marker was preserved after the current SDK rejected it.

## Hosted bridge

The Dev-only **Settings → Dev Bridge** screen uses WalletConnect to approve
the pinned `dev.mint.utexo.com` origin. A usable confirmed RGB output is
required for the hosted frontend's blind-invoice capability. The wallet
requests separate consent for the invoice, burn and proof. An accepted burn
can be found under the website's Existing Burn flow in the approved session.
**Saved burns** in Aster can export an authenticated `.utexoburn` file for
upload after the browser session is lost. Restart recovery reads existing
receipts. It can release an exact unsubmitted burn reservation without
broadcasting a payment.

The current local iOS simulator candidate uses the verified ABI 6 BFA.7
native fixture. The distributed ABI 5 SDK still supports the dedicated Dev
wallet and leaves the bridge screen gated. The hosted pairing and funded
mint, burn and payout round trip are pending manual verification. Production
RGB_L1, Lightning and spending from restored snapshots remain gated.
