# Dev Signet USDT readiness

Reviewed 2026-11-07 against the Iris chat (`Dev`, WDK/Iris project), its current
candidate configuration, and [WDK PR 23](https://github.com/UTEXO-Protocol/wdk-wallet-rgb/pull/23).
This is a compatibility record, not permission to start a wallet or spend funds.

## Two different Signet chains

Public Signet and UTEXO Dev Signet share Bitcoin's Signet network encoding but
have different chain histories. A `tb1` address, a network name, or a healthy
HTTP response cannot establish that the wallet is on the intended chain.
Dev uses block 1 hash
`0000001b808e4ece11c0cd922eaf9eee8d7dfba7e23e90b4f9614248daaf72cb`.
Both wallet synchronization and RGB validation must enforce that checkpoint
before Dev is enabled. An existing public Signet wallet must never be reopened
against Dev merely because both profiles say `signet`.

| Requirement | Current evidence | Disposition |
| --- | --- | --- |
| Dev Bitcoin indexer | `https://dev.esplora-01.mint.utexo.com` | Private Dev access; never substitute public Signet Electrum or mempool.space. |
| Dev RGB proxy | `rpcs://dev.rgb-proxy.utexo.com/json-rpc` | Current RGB generation uses proxy protocol 1.0; legacy RLN proxy 0.2 is incompatible. |
| BFA backing chain | Arbitrum One, chain `42161`, reference RPC `https://arb1.arbitrum.io/rpc` | Separate from the Bitcoin chain identity; require explicit RPC and expected chain ID. |
| Deployed Dev generation | BFA.6, source `5010eefa355beb9c42a4c1b69883f7651241a111`, connector `0.1.0-207` | [DevOps 217](https://github.com/UTEXO-Protocol/devops/pull/217), [readiness correction 218](https://github.com/UTEXO-Protocol/devops/pull/218). |
| Iris/WDK candidate generation | BFA.7, source `9ec49c08be2e68f08521281e3efbd760ec989cb9`, WDK `2.1.0-alpha.12` | BFA.7 retains BFA.6's schema. Its Bare addon cannot replace Flutter's UniFFI libraries. |
| Flutter RGB_L1 generation | BFA.5, source `0a9d352f2690902df2b6fae9bca1a6c13c3354d4` | Incompatible with the newly issued Dev asset. Aster's RGB_L1 runtime and release gates remain closed. |
| Mobile distribution | Android Maven still lists BFA.5; Swift published BFA.6 on November 6 | No qualified matching Android/iOS pair is wired into this SDK. Do not advance just one platform or relabel BFA.5 bytes. |
| Current Dev asset | `rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE`, Bridged USDT / BUSDT | Issuance reported in DevOps 217. Approved standalone contract bytes, digest and independently validated precision are missing. Not an admitted wallet asset. |
| Historical asset | `rgb:fbkO6B_i-qyLXa6d-x3sAOaX-cx~vZB9-rxNSUle-9lXBTf8`, Bridged USDT / BUSDT, 6 decimals | Historical BFA.5 export SHA-256 `a678ebf73f3a0523b307cd2fe8019a321ac938eaf547c2c65a7ac079948332ce`; Iris marks it unadmitted. Never substitute it for the new asset. |
| Latest referenced Dev E2E | [Run 42261217049](https://github.com/UTEXO-Protocol/bridge/actions/runs/42261217049) failed while waiting for the UI mint-confirmation button | This is not evidence of a native mint or chain-settlement defect, and does not qualify a wallet round trip. |

## Required before Dev USDT can be used

1. Obtain the issuer-approved **current** contract export and SHA-256. Validate
   the exact asset ID, BFA schema, Bitcoin chain/checkpoint, native name, ticker,
   precision, backing chain and contract metadata. A display ticker is never
   asset identity. Re-exporting an old schema cannot preserve an ID committed to
   a different schema.
2. Supply matching, verified Android and iOS native bindings with standalone
   genesis registration. Import must be idempotent and verify the expected ID
   without crediting funds. The current Flutter RGB_L1 UniFFI API lacks this
   operation; a Dart stub cannot implement it safely.
3. Qualify Dev checkpoint enforcement through both native sync and RGB
   validation, guarded network access, and exact EVM chain binding. Availability
   checks alone do not establish deployment identity.
4. Implement and qualify RGB_L1 durable send and backup recovery before lifting
   Aster's gate. Bind a fresh wallet's immutable deployment identity to its
   storage. Never reuse public Signet or legacy BFA.5 state for this test.
5. Bootstrap the approved metadata before generating an asset-bound first
   witness invoice. Verify receive, balances, send, history and restart using
   that exact contract on both mobile platforms. Keep BTC and asset amounts
   exact and distinguish submitted from confirmed payments.

Aster currently rejects the explicit Dev profile, known Dev service hosts and
known Dev asset IDs before opening wallet state. Newly provisioned Signet
wallets persist their explicit deployment identity. Older Signet records retain
an unknown identity and cannot activate against a newly selected chain; they
are not relabelled or deleted. A full Dev checkpoint-bound deployment remains
an activation prerequisite. Merely supplying
`ASTER_USDT_ASSET_ID` cannot authorize Dev. Public Signet BTC-only testing can
use `config/signet-public.debug.json` with a fresh wallet and no USDT definition.
This is a Debug test configuration, not a release manifest. Hosted
Dev USDT testing remains blocked by the requirements above. No stack reset,
container creation, wallet migration or funded operation forms part of this
readiness review. Lightning remains outside the release scope.
