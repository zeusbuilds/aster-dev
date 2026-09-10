# Aster Local Regtest

## Ownership

Aster owns the Compose project `aster-app-regtest`, network
`aster-app-regtest-network`, and state under `.local/aster-regtest/` in this
checkout. These resources carry the `com.aster.owner=aster-dev` label. This is
a development chain with valueless test coins, not a release deployment.

Never stop, reset, recreate, inspect secrets from, or reuse the external
`rgb-lightning-node-perf-lab`, Iris-owned wallet stack, or SDK regtest
projects. Do not run their `regtest.sh` scripts. Their containers, wallets,
networks, and data are not Aster dependencies.

| Service | Host endpoint | Persistent state |
| --- | --- | --- |
| Bitcoin Core 30.0 | `127.0.0.1:19443` RPC | `.local/aster-regtest/bitcoind/` |
| Electrs 0.10.10 | `127.0.0.1:51001` Electrum TCP | `.local/aster-regtest/electrs/` |
| RGB proxy 0.3.0 | `rpc://127.0.0.1:3100/json-rpc` | `.local/aster-regtest/proxy/` |
| Miner / faucet | No published port | `aster-faucet` wallet inside Bitcoin state |

The app's embedded native node uses ports `19735` (daemon) and `19736`
(Lightning peers) in the generated local configuration. The normal SDK
defaults `9735`/`9736` can collide with other simulator wallets on the host.
These are app-process listeners, not Docker services or provisioned channels.

## Initialize And Run

From the app root, initialize once:

```sh
fvm dart run tool/initialize_local_regtest.dart
docker compose --env-file .local/aster-regtest/compose.env -f ops/regtest/compose.yaml up -d --wait --wait-timeout 180
docker compose --env-file .local/aster-regtest/compose.env -f ops/regtest/compose.yaml ps
```

The initializer refuses existing state/configuration and symlinked local or
configuration roots. It generates independent random RPC credentials inside
a mode-700 directory; credential files are mode 600. It writes only public,
non-secret defines to ignored `config/regtest.ios.local.json`. Never commit
these files, print interpolated Compose configuration, or treat `.local` as a
build cache. An interrupted initialization preserves partial state for manual
inspection, not automatic deletion or password rotation.

Run `up` again to restart existing services; do not rerun initialization.
Before starting, check that `19443`, `51001`, `3100`, `19735`, and `19736` are
free or already owned by this exact Aster setup. A collision is a reason to
choose new Aster ports and update its local config, never stop another app.

Build and run on an explicitly selected Aster-only iOS simulator:

```sh
make verify-generated ios-dependencies
BUNDLE_FROZEN=true BUNDLE_PATH="$PWD/.bundle" bundle exec fvm flutter run --no-pub -d <ASTER_SIMULATOR_ID> --dart-define-from-file=config/regtest.ios.local.json
```

For Android, create a separate ignored local JSON config using `10.0.2.2`
instead of `127.0.0.1` for the indexer and proxy hosts; keep the Aster ports.
Then pass that file to `fvm flutter run --no-pub -d <ASTER_DEVICE_ID>` with
`--dart-define-from-file`. The Android runtime has not been qualified against
this new stack. Never target an Iris emulator.

## Health, Mining, And Funding

The miner creates or loads only `aster-faucet`, bootstraps a new chain to at
least 101 blocks, and mines one block every ten seconds. It never resets an
existing chain. Stop/start only the miner service to control confirmations:

```sh
docker compose --env-file .local/aster-regtest/compose.env -f ops/regtest/compose.yaml stop miner
docker compose --env-file .local/aster-regtest/compose.env -f ops/regtest/compose.yaml start miner
docker exec aster-app-regtest-bitcoind-1 bitcoin-cli -regtest -datadir=/srv/app/.bitcoin getblockchaininfo
```

Create a **test-only** wallet in Aster, select Receive > Bitcoin onchain, then
fund its actual `bcrt1...` address from the isolated faucet:

```sh
docker exec aster-app-regtest-bitcoind-1 bitcoin-cli -regtest -datadir=/srv/app/.bitcoin -rpcwallet=aster-faucet sendtoaddress <ASTER_REGTEST_ADDRESS> 0.01
```

After mining/indexing, refresh Home to synchronize. An unfunded wallet starts
with zero; the app does not invent a balance. Never import a real-funds seed
into this simulator. Do not post mnemonics or RPC credentials in diagnostics.

Bitcoin RPC, proxy JSON-RPC, and miner heartbeat have bounded health checks.
Electrs' container health checks its listener; verify actual indexing with
the Electrum `blockchain.headers.subscribe` method when collecting evidence.
Bitcoin P2P listening is explicitly enabled for electrs inside the isolated
Docker network even with outbound peers disabled by `-connect=0`. P2P is not
published to the host. Startup failure or unhealthy status is not a readiness
pass. Logs are size-bounded but may still be sensitive; inspect them locally.

## Capabilities And Limits

This stack supplies Bitcoin regtest, an Electrum indexer, and RGB consignment
transport. It does **not** provision an RGB USDT contract, LSP, peer/channel
liquidity, VSS backup, or explorer. USDT stays unavailable without a real
configured contract ID/precision; Lightning payments require real channels
and liquidity. Healthy containers do not prove funded wallet flows or all
four payment options. Full exact-candidate qualification remains TEST-019.

Images are pinned to immutable digests in `ops/regtest/compose.yaml`, using
the locally available Hashbeam Bitcoin/electrs packaging and RGB-Tools proxy.
The proxy's OCI metadata identifies source revision
`f466a580b1108580a922b098dc6952b4bde219cb` and MIT licensing. The Hashbeam
wrappers do not provide complete source/license attestations in their inspected
OCI labels. Digests establish identity, not independently verified provenance,
licensing completeness, signatures, or reproducible builds. These images are
local development dependencies, not an approved production supply chain.

App endpoint policy rejects protected ports `18443`, `50001`, and `3000` on
loopback and Android emulator host aliases. Noncanonical numeric aliases such
as `127.1` fail before native use. Insecure local transport is Debug/Profile
only; this config intentionally cannot qualify a Release artifact, which
requires explicit TLS-protected endpoints and the release manifest gate.
