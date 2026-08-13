# UTEXO Wallet Architecture

This document describes the architecture that exists in this repository. It is
an implementation contract, not an aspirational component list.

## Dependency Rule

```text
View -> ViewModel -> Repository -> SDK/service/storage/network
```

- Views render immutable state and send user intent to a ViewModel.
- Generated Riverpod Notifiers and AsyncNotifiers own feature orchestration.
- Repositories own domain rules, mutation ordering, and infrastructure calls.
- Adapters isolate plugins, native SDK types, storage formats, and wire data.
- No use-case layer exists. Adding one requires evidence that the existing
  repository/ViewModel boundary cannot express the behavior cleanly.

Dependencies point inward toward app-owned contracts. Presentation never calls
`rgb_sdk_flutter`, HTTP, secure storage, SharedPreferences, camera, clipboard,
share, URL-launcher, package metadata, or haptic plugins directly.

## Repository Layout

```text
lib/
  core/          bootstrap, configuration, DI, errors, network, platform, storage
  features/      feature-owned domain, data, ViewModels, screens, and widgets
  shared/        routing, design system, feedback, layout, motion, formatting
  main.dart      root app and authoritative Flutter lifecycle observer
```

A feature creates only the layers it needs. Shared code must represent a real
cross-feature contract; it is not a holding area for convenient utilities.

## State And Riverpod

- Providers are generated from `@riverpod` declarations where state ownership
  is required.
- State flows down; commands flow up.
- Route-scoped edit state uses auto-dispose families.
- Runtime/repository owners are keep-alive and disposed by bootstrap ownership.
- Operation state is specific enough to disable only conflicting actions.
- Widgets do not start asynchronous initialization from `build`.
- Overlapping mutations are rejected or serialized at their owning boundary.
- Provider overrides supply tests with app-owned fakes, not production fixtures.

## Native Wallet Ownership

`WalletRuntime` is the only app-owned lifecycle owner. It serializes native
initialization, unlock, sync, suspend, resume, reinitialization, switching, and
destruction. The queue is not released while an uncancellable SDK future may
still be running.

`RgbWalletEngine` is the only adapter that retains `UtexoWallet`. It validates
and converts native models to app-owned domain values. SDK DTOs, Pigeon maps,
and native exception payloads do not reach repositories, ViewModels, or UI.

Provisioning is transactional:

1. Generate opaque wallet and ownership identifiers from secure randomness.
2. Persist a staged metadata record and encrypted credential envelope.
3. Create/open the native wallet through the runtime queue.
4. Commit the profile as ready only after native activation succeeds.
5. Roll back only resources whose ownership token is proven.

Bootstrap reconciles interrupted states before opening the durable active
wallet. Ambiguous or legacy data fails closed and remains preserved.

## Domain Model

Asset, rail, and environment are independent:

- product asset: Bitcoin or an RGB contract
- rail: on-chain or Lightning
- environment: regtest, signet, or mainnet

RGB USDT identity comes from a deployment-owned contract ID and precision, not
from the `USDT` label. Monetary values use integer sats, millisats, or RGB
smallest units. Fiat uses integer minor units after repository validation.

Activity normalizes Bitcoin transactions, Lightning payments, and RGB
transfers into stable opaque IDs while preserving rail, native identifiers,
status, exact amount, fee, and optional metadata. Conflicting duplicate IDs
fail closed.

## Failures And Reliability

Repositories and ViewModels expose sealed `AppResult<T>` values. `AppFailure`
contains a stable category, code, retryability, optional retry delay, user-safe
message, and bounded diagnostic cause. Raw exception text, response bodies,
native payloads, paths, payment material, and secrets are not UI or log data.

App-owned HTTP uses one abortable operation budget. Only idempotent GET requests
retry with bounded exponential backoff and jitter. Mutations never retry without
a real idempotency contract. Native operation timeout and quarantine behavior
remain SDK-owned so Dart cannot release serialization while native work runs.

## Routing

GoRouter routes carry stable public identifiers, never secret or native
objects. Payment routes carry a product asset/rail slug; repositories resolve it
to deployment configuration. Transaction details route by opaque activity ID
and reload from the repository. Durable active-wallet state guards wallet-only
routes and onboarding replaces the root only after a committed provision.

## Presentation Contracts

`ThemeData`, `ColorScheme`, `TextTheme`, and semantic `ThemeExtension`s own
visual decisions. The existing palette is fixed. DM Sans is the UI typeface;
Public Sans applies only to numeric spans through `AmountText`/`NumericText`.
Cards, fields, sheets, and tiles use squircles; intended pills use stadium
geometry; only truly circular affordances use circles.

Shared services own haptics, queued toasts, reduced-motion policy, and window
insets. Mutation buttons remain loading on the current screen until confirmed
completion. Disabled controls emit no action or haptic. Initial loading uses
layout-preserving shimmer; refresh retains existing content.

## Security Boundaries

- Recovery phrases and database passwords use device-bound secure storage.
- Wallet files use native owner-only/no-backup policy.
- Route arguments, preferences, logs, analytics, and diagnostics never carry
  recovery material.
- Public URLs and runtime endpoints are validated before use.
- Build defines contain non-secret deployment identity only.
- Secret-disclosure authentication and screen-capture behavior remain explicit
  blocked product decisions, not implicit platform defaults.

## Verification

Host gates cover formatting, generated code, fatal analysis, tests, Dartdoc,
architecture direction, adapter ownership, barrel policy, and tracker
inventory. `make verify-architecture` parses every owned Dart import and fails
when domain/data direction or infrastructure ownership regresses. Release
qualification additionally
requires exact-commit native tests, iOS/Android builds and runtime smokes,
configured-wallet restart evidence, accessibility checks, and measured profile
performance/memory. The tracker records what actually ran and preserves every
accepted constraint and blocker.
