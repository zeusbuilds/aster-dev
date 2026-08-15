# Regtest Isolation

An external Docker Compose project named `rgb-lightning-node-perf-lab` owns
ports `18443`, `50001`, and `3000` and persistent data outside this repository.
It is not an app test dependency.

Never stop, reset, recreate, inspect secrets from, or reuse that project's
containers, networks, volumes, bind mounts, or data. Never run its existing
`regtest.sh` from app work.

The app has no committed regtest stack today. If one is introduced, it must:

1. use an app-owned Compose project name
2. use separate app-owned bind-mounted data directories
3. publish only currently free host ports other than the protected ports
4. pin every image by immutable digest and record licenses/provenance
5. expose credentials through ignored local environment files, never source
6. provide health checks and deterministic funded/unfunded setup
7. clean up only resources labeled as owned by that app project

`AppEnvironment` accepts only canonical endpoint hosts and rejects the
protected ports for loopback, expanded or IPv4-mapped IPv6 loopback, and the
Android emulator host alias. Legacy numeric aliases such as `127.1` are
rejected before resolver or native-SDK use. Regtest evidence must record the
exact configuration without recording RPC, LSP, VSS, or proxy credentials.
