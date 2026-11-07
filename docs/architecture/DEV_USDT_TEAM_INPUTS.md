# Team inputs for the current Dev BUSDT

These inputs are required before admitting the hosted Dev asset. They do not
lift the RGB_L1 runtime or release gates. Reviewed on 2026-11-07.

## Message to send

Please provide the issuer-approved **standalone RGB genesis contract export**
for the current Dev BUSDT and its SHA-256. The expected current asset ID is:

`rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE`

Please confirm:

1. This export is the asset currently deployed by the Dev bridge, using the
   BFA.6 schema that is compatible with BFA.7. If the deployment has changed,
   supply the replacement asset ID, export, digest and deployment revision
   together. The old BFA.5 asset and a burn-proof/transfer consignment are not a
   standalone genesis export for this asset.
2. Its exact native metadata: **Bridged USDT / BUSDT**, precision, schema, and
   reject-list configuration. We will decode and validate these against the
   approved file; the historical asset's six decimals are not evidence for the
   new asset.
3. The backing deployment: **Arbitrum One, chain 42161**, the exact token
   contract, BFA locking/backing contract addresses, and the bridge/connector
   revision associated with this RGB asset. Identify the approved RPC endpoint.
   A Bitcoin Signet network name does not identify the EVM backing chain.
4. The approved BFA.7 `min_mint_lock_blocks` and `max_mint_lock_blocks` policy
   for that backing chain. These are **Arbitrum blocks**, not Bitcoin blocks.
   The earlier Iris candidate's 2/7200 settings are reference values, not an
   approval of the current deployment's risk policy.

For the subsequent hosted test, please also confirm the device's NetBird/VPN
access and whether either service requires wallet-specific authentication.
Provide credentials through the approved secret channel, never a source file
or build define. We will need confirmed **Dev-chain** BTC at a new test-wallet
address and either a small transfer of this exact BUSDT from an existing wallet
or a funded, authorized Dev bridge account for mint testing. If testing mint and
burn, confirm the supported Arbitrum token, minimum amounts after fees, gas and
payout capacity.

## Inputs already known

| Item | Recorded value |
| --- | --- |
| Bitcoin deployment | Custom Dev Signet, distinct from public Signet |
| Block-one checkpoint | `0000001b808e4ece11c0cd922eaf9eee8d7dfba7e23e90b4f9614248daaf72cb` |
| Esplora | `https://dev.esplora-01.mint.utexo.com` |
| RGB proxy | `rpcs://dev.rgb-proxy.utexo.com/json-rpc`, protocol 1.0 |
| Bridge origin | `https://dev.mint.utexo.com` |
| Reference EVM RPC | `https://arb1.arbitrum.io/rpc` |
| Last reviewed deployed native source | BFA.6 `5010eefa355beb9c42a4c1b69883f7651241a111` |
| Flutter candidate source | BFA.7 `9ec49c08be2e68f08521281e3efbd760ec989cb9` plus recorded Flutter integration patches |

The former asset `rgb:fbkO6B_i-qyLXa6d-x3sAOaX-cx~vZB9-rxNSUle-9lXBTf8`
and export digest
`a678ebf73f3a0523b307cd2fe8019a321ac938eaf547c2c65a7ac079948332ce`
remain historical BFA.5 evidence and are not admitted as current Dev USDT.

Sources: [Dev issuance](https://github.com/UTEXO-Protocol/devops/pull/217),
[deployed revision correction](https://github.com/UTEXO-Protocol/devops/pull/218),
[BFA.7 WDK candidate](https://github.com/UTEXO-Protocol/wdk-wallet-rgb/pull/23).
The approved current export and digest were absent from the reviewed Iris
profile and candidate records; they must come from the issuer/deployment owner.
