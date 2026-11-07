# Existing local BFA.7 qualification reference

Read-only inventory on 2026-11-07. This does not authorize replaying another
consumer's operations or prove the Flutter candidate has passed funded tests.
The shared stack's `AGENTS.md`, `docs/CONSUMERS.md`, `artifacts/consumer-config.json`,
runbook, validation notes and source manifest were read first. Its historical
BFA.5/proxy-0.2 registry is not the BFA.7 fixture below.

The already running Docker project is `utexo_wdk_onchain_bfa7_fixture`, owned by:

`/Users/hardik/Projects/utexo-wdk-onchain-candidate/sdk-alpha12-funded-android`

| Service | Existing host endpoint | Read-only observation |
| --- | --- | --- |
| Bitcoin Core | `http://127.0.0.1:49743` | Use the fixture's admitted RPC/auth helper; never print credentials. |
| Esplora | `http://127.0.0.1:49794` | Tip 165 at inspection. |
| Fulcrum | `tcp://127.0.0.1:49702` | Admitted fixture indexer; use explicit test fee rates. |
| RGB proxy | `rpc://127.0.0.1:49790/json-rpc` | `server.info` reported protocol 1.0, proxy 0.4.0. |
| Local backing EVM | `http://127.0.0.1:49745` | `eth_chainId` returned `0x7a69` (31337). |

The fixture's **backing EVM is 31337**. `eip155:42161` in its Iris/WebRGB records
is a committed burn **destination route**, not the backing RPC's chain identity.
Do not copy that route as the backing EVM configuration. The optional Iris-only
Electrum fee wrapper on port 49712 synthesizes 1 sat/vB; it is a test oracle,
not a market quote or a production endpoint.

Public asset provenance:

- Native upstream BFA.7 source: `9ec49c08be2e68f08521281e3efbd760ec989cb9`.
- Asset: `rgb:kOryemwN-I8Iutl8-otIPmDa-rn1cPTq-7VuhGvS-oe6oiMc`.
- Native metadata: `WDK L1 Qualification BFA`, `QBFA`, precision 6.
- Artifact: `fixture/runtime/issuer/public-contract.rgb` under the owner directory.
- Artifact length: 444 bytes.
- SHA-256: `189674bd83baa0a74c06f86d4652d896e7725f33285b9e25c8006b2087044cb0`.

The owner's `QUALIFICATION.md`, `fixture/runtime/chain.json`,
`evidence/fixture-identity.json` and `evidence/funded-result.json` record its
qualification. WDK alpha.12 SDK commit `acc8c703aeed2a2b1f5f14a50d219fd4abe7f3d9`
passed its 14 recorded Android phases. Those results are reference evidence;
they do not qualify Flutter's independently patched native artifact.

Preserve all containers, chain state, contracts, issuer wallets and existing
journals. Do not run `initialize`, bootstrap/recovery/deploy commands, reset an
AVD or replay an existing runner. The fixture is also used by Iris testing.
A Flutter run needs its own separate wallet directories and operation journals.
Coordinate mining/funding with the fixture owner before invoking monetary
helpers. `fixture.py fund ADDRESS SATS UNIQUE-LABEL` accepts 1,000–10,000,000
regtest sats, writes a new intent and mines three blocks. `issuer.py` serializes
its existing-asset operations with `.issuer.lock`; it must not be used
concurrently with the Iris qualification suite or replay an uncertain intent.

No containers were started, created or reset, and no wallet, contract, funding
or mining action was performed to produce this inventory.

## Flutter consumer transport and later evidence

The RGB_L1 native regtest egress policy uses actual loopback endpoints. An
Android emulator consumer needs owned `adb reverse` mappings for each selected
fixture port and loopback URLs inside the app; the legacy adapter's general
`10.0.2.2` allowance is not admission for the RGB_L1 native runtime. Inspect for
existing mapping conflicts first, preserve other consumers' mappings and remove
only mappings owned by the qualification run. This does not add a proxy service,
container or chain. Do not relax the native network policy to make a local test
configuration work.

Subsequent separately authorized Flutter host/iOS qualification created fresh
private test wallets, used tiny existing-asset transfers and append-only mining,
and preserved all existing fixture state. The SDK's
`doc/BFA7_QUALIFICATION.md` records exact source/compiler/contract identities,
actual success/restart and lost-reply proofs, corrections, retained failures,
and remaining gates. Those later actions are not part of the read-only inventory
above and do not admit hosted Dev USDT, mainnet or RGB_L1 product activation.
