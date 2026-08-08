# UTEXO Wallet Production Refactor Tracker

This is the release-candidate source of truth for the app refactor. A green
build is necessary but is not sufficient: every repository-owned file must be
reviewed, every finding must have evidence, and every claimed behavior must be
verified on the exact candidate commit.

## Scope And Status

- Baseline commit: `bbbc315634bba975ed767de378ff155e08a0ba15`
- Baseline date: 2026-08-08 (Asia/Kolkata)
- Target product: UTEXO Bitcoin, RGB USDT, and Lightning wallet
- SDK target: `rgb_sdk_flutter` at `3dd82e23d80bb4bb6a2d2526c6c6741ac1ea1236`
- Current phase: Phase 3, design system and shared UX
- Release status: not eligible for funds-bearing release

Statuses are `unreviewed`, `reviewed-clean`, `fixing`, `verified`, `blocked`,
and `accepted-constraint`. A finding is only `verified` when its implementation
and relevant tests/builds have passed on the recorded commit.

## Accepted Constraints

| ID | Source | Status | Constraint | Release consequence |
| --- | --- | --- | --- | --- |
| CON-001 | SDK PKG-006 | accepted-constraint | The pinned SDK accepts upstream native artifact provenance for internal beta and does not establish a funds-bearing mainnet production supply chain. | The app cannot truthfully claim funds-bearing mainnet production readiness while this remains accepted. |
| CON-002 | Product | accepted-constraint | No real swap backend is available. | Swap may provide selection and explanatory UI, but execution and success must remain unavailable. |

## Decision Log

| ID | Status | Decision | Rationale / follow-up |
| --- | --- | --- | --- |
| DEC-001 | verified | Commits use repository-local `zeusbuilds <zeusbuilds113@gmail.com>`. | Global Git identity remains untouched. |
| DEC-002 | verified | Keep simplified Riverpod MVVM with no use-case layer. | Required architecture boundary. |
| DEC-003 | verified | Preserve the existing palette, DM Sans UI type, and Public Sans numeric type. | Locked product/design direction. |
| DEC-004 | verified | Consume only the SDK stable public API at the immutable target commit. | Prevents accidental coupling to raw native DTOs. |
| DEC-005 | verified | Any app regtest environment must be isolated from `rgb-lightning-node-perf-lab`. | Prevents mutation of the existing shared chain and index state. |
| DEC-006 | blocked | Final iOS bundle ID, Android application ID, display name, and signing ownership are not yet confirmed. | Must be decided before release platform configuration and migration of secure-storage namespaces. |
| DEC-007 | verified | Use exact compatible releases `flutter_riverpod` 3.3.2, `riverpod_annotation` 4.0.3, `riverpod_generator` 4.0.4, and `build_runner` 2.15.1 on Flutter 3.44.9. | This set resolves with Flutter's pinned `meta` 1.18.0 and `test_api` 0.7.11 and uses analyzer 12.1 with Dart 3.12 support. Riverpod 3.4 / generator 4.0.8 requires newer SDK-pinned packages and was solver-tested but rejected. Upgrade atomically when Flutter advances those pins. |
| DEC-008 | verified | Keep `flutter_secure_storage` at 10.3.1 on this toolchain. | Version 11 requires Android compile SDK 37 while Flutter 3.44.9 templates target SDK 36. Re-evaluate with the next coordinated Flutter/platform upgrade. |
| DEC-009 | verified | Keep Flutter 3.44's generated legacy Kotlin compatibility flags until a supported built-in Kotlin migration is available. | Flutter's app migration guide requires Flutter 3.47 or newer. The current AGP 9.0.1/Kotlin 2.3.20 build passes, but the app and affected plugins must migrate before Flutter removes compatibility. |
| DEC-010 | verified | Keep iOS plugin integration on CocoaPods for the pinned SDK revision. | The SDK does not currently declare Swift Package Manager support. Flutter's generated package scaffolding remains tool-owned and ignored. |
| DEC-011 | verified | Store a random 256-bit native database password and the recovery mnemonic as one versioned per-wallet record in platform secure storage. | The product has no PIN/biometric unlock contract yet. iOS uses a non-synchronizing, this-device-only Keychain class; Android uses namespaced AES-GCM storage with destructive reset disabled. Platform round-trip tests pass at `1b3273a`; a later authentication UX may add user-presence controls without changing repository contracts. |
| DEC-012 | verified | Use one sealed `AppResult<T>` / `AppFailure` convention at repository and ViewModel boundaries. | SDK exceptions retain typed diagnostic causes internally, while UI receives stable redacted messages and retryability metadata. Fault and redaction tests pass at `1b3273a`. |
| DEC-013 | verified | Represent Bitcoin/RGB asset identity, payment rail, and blockchain environment as independent app-owned types. | Integer domain types and native boundary validation pass at `1b3273a`; legacy feature UI migration remains separately tracked by DOMAIN-001. |
| DEC-014 | verified | Serialize all SDK access through one app-owned wallet runtime owner. | Runtime, repository, lifecycle, switching, reinit, and fault-path tests pass at `1b3273a`. |
| DEC-015 | verified | Do not wrap native SDK calls in an app-side timeout that releases the serialization queue while native work may still be running. | The pinned SDK owns typed native timeout/quarantine behavior. The app adds bounded network timeouts around app-owned HTTP only; runtime ordering tests pass at `1b3273a`. |
| DEC-016 | verified | Protect wallet files with foreground-only iOS data protection and exclude them from backup; disable Android cloud backup and device transfer. | Native bridge and real platform tests prove the file policy; the exact Android release manifest proves backup/transfer exclusion at `1b3273a`. |
| DEC-017 | verified | Reject the pre-existing protected regtest host ports from app configuration. | Configuration tests at `1b3273a` reject `18443`, `50001`, and `3000` on loopback and Android emulator host aliases. No protected stack resource was inspected or mutated. |
| DEC-018 | fixing | Preserve the established shape language: true stadium geometry for pills, rounded superellipses for cards/tiles/fields/sheets, and circles only for circular affordances. | ThemeData, shared controls, and feature surfaces must share this policy; no palette or font values change. |
| DEC-019 | fixing | Runtime window insets are layout environment, not spacing tokens. | Move `padding`, `viewPadding`, and `viewInsets` access to a typed window-insets API; use `SafeArea` for ordinary roots and explicit persistent/keyboard insets only where composition requires them. |
| DEC-020 | fixing | Route all tactile feedback through one injectable semantic haptic service. | Capability probing is shared/cached; library failures are swallowed; disabled/loading/cancelled interactions emit nothing; result haptics occur only after confirmed outcomes. |
| DEC-021 | fixing | Present transient messages through one bounded FIFO toast queue with deduplication and an app-root host. | Remove static overlay ownership and SnackBar divergence; support success/failure/warning/info, accessible dismissal, safe text, and reduced motion. |
| DEC-022 | fixing | Resolve animation durations through one reduced-motion policy and mute offscreen feature tickers. | `MediaQuery.disableAnimations`/platform accessibility must collapse decorative transitions while retaining final state and truthful loading status. |

## Baseline Evidence

| Check | Baseline result | Evidence / implication |
| --- | --- | --- |
| Git | Pass | Clean `main` tracking `origin/main`; repository-local Zeus identity. |
| Format | Pass | 180 Dart files checked, 0 changed. |
| Analyze | Pass | Flutter 3.38.9 reported no analyzer issues with fatal warnings and infos. Current lint policy is minimal. |
| Tests | Pass, inadequate | Two design-token assertions in one test file; no wallet behavior coverage. |
| Dart documentation | Warning | Two unresolved `[enableLogging]` references. |
| Dependencies | Action required | 37 direct constraints block newer resolvable versions; `intl` uses `any`; several transitive packages are discontinued. |
| iOS simulator | Pass with warnings | Built and launched commit `bbbc315` on iPhone Air / iOS 26.5. Five `mobile_scanner` native warnings. |
| Android debug APK | Blocked | Gradle distribution download timed out before compilation. This is baseline environment evidence, not an Android code pass. |
| Accessibility snapshot | Fail | Import fields are absent from the semantic target tree; several controls have empty or duplicate labels. |
| Product truth | Fail | Shell balances and transactions are static, Send is prefilled with a sample address, and unfinished flows are reachable. |

Baseline screenshots are stored in `docs/release/evidence/baseline/`.

## Phase 1 Evidence

| Check | Result | Exact evidence |
| --- | --- | --- |
| Implementation commit | Recorded | `8e97370` (`Modernize Flutter foundation and remove unsafe wallet scaffolding`). |
| Toolchain | Pass | Flutter 3.44.9, framework `6b182d2c7585eba26d4edce0f97630effd256c33`; Dart 3.12.2. |
| SDK resolution | Pass | `pubspec.lock` resolves the public UTEXO Git dependency to immutable commit `3dd82e23d80bb4bb6a2d2526c6c6741ac1ea1236`. |
| Generation | Pass | `fvm dart run build_runner build`; five Riverpod source inputs produced ten ignored outputs with analyzer 12.1 and no language-version warning. |
| Format | Pass | `fvm dart format --output=none --set-exit-if-changed .`; 160 files, zero changed. |
| Analyze | Pass | `fvm flutter analyze --fatal-warnings --fatal-infos`; zero diagnostics. |
| Tests | Pass, still inadequate | Two existing token tests pass. TEST-001 remains open because this is not behavioral release coverage. |
| Dart documentation | Pass | `fvm dart doc --validate-links`; 153 libraries, zero warnings and zero errors. |
| iOS simulator | Pass with tracked warnings | Debug simulator build, install, and launch on iPhone Air / iOS 26.5 passed. No Flutter/app exception was recorded; SDK SwiftPM support remains SDK-002 and simulator accessibility noise remains TOOL-002. |
| Android debug APK | Pass with tracked warning | `fvm flutter build apk --debug --target-platform android-x64`; 319,965,355 bytes, SHA-256 `f979afeff4dc8af870c02e11a91c05dc113377300a84d15e9de0c3caa36371a3`. Built-in Kotlin migration remains PLAT-002. |
| Tracker inventory | Pass | 248 non-generated files after Phase 1 removals, including the SDK integration guide; validator passes. |
| Host storage incident | Recovered | The first exact Android package attempt exhausted disk space after successful compilation. Only disposable build/application caches were removed; the protected regtest stack, simulator/emulator data, source, and user data were not touched. The identical command then passed. |

## Phase 2 Evidence

| Check | Result | Exact evidence |
| --- | --- | --- |
| Implementation commit | Recorded | `1b3273a` (`Harden wallet runtime and persistence boundaries`). |
| Generation | Pass | `fvm dart run build_runner build` produced the expected Riverpod outputs; an immediate second run skipped all 197 inputs and wrote zero outputs. |
| Format | Pass | `fvm dart format --output=none --set-exit-if-changed .`; 204 files, zero changed. |
| Analyze | Pass | `fvm flutter analyze --fatal-warnings --fatal-infos`; zero diagnostics. |
| Host tests | Pass | `fvm flutter test --coverage`; 137 tests passed. Fault coverage includes lifecycle serialization, reinit/rollback, unknown outcomes, registry corruption/torn writes, ownership collisions, redaction, transport budgets/cancellation, native mapping, and market-data truth. |
| Coverage | Partial, tracked | 2,454 of 7,085 instrumented Dart lines, 34.64%. Phase 2 runtime/repository/storage/network layers are covered materially; TEST-001 remains open for UI, accessibility, golden, end-to-end, and performance evidence. |
| Dart documentation | Pass with clean output | Fresh isolated output: 178 libraries, zero warnings and zero errors. Reusing stale ignored `doc/api` output produced 217 obsolete-file warnings; repeatable cleanup remains DOC-004. |
| iOS native integration | Pass | iPhone Air simulator, iOS 26.5: secure-storage namespace round trip and native wallet-file policy both pass. |
| Android native integration | Pass | `Utexo_API_36`, Android 16/API 36: the same two secure-storage and native-file-policy tests pass. The emulator was stopped after the run. |
| iOS simulator build | Pass with tracked warning | `fvm flutter build ios --simulator --debug`; 123,808-byte Runner executable, SHA-256 `32c455cff328dfa8af35f1b299d4f1ce9f79e7ebb4d1734c0454d898685eee73`. SDK SwiftPM remains SDK-002. |
| Android release build | Pass with tracked constraints | `fvm flutter build apk --release --target-platform android-arm64`; 247,770,950-byte APK, SHA-256 `425ca0652fc6c08d1bca1745db75f19a290bccddd0155714526576bb9730a3ba`. Manifest has `allowBackup=false` and `usesCleartextTraffic=false`; release is signed by Android Debug and therefore PLAT-001 remains blocked. Kotlin migration remains PLAT-002. |
| Physical iOS | Blocked evidence | Build/install succeeded on device `00008130-000A552C3EBA001C`, but Flutter could not attach to its VM service over the wireless/local-network path. TOOL-003 remains open for physical runtime, haptics, performance, and memory proof. |
| Tracker inventory | Pass | 295 non-generated repository files; inventory validator and staged diff checks pass. |
| Delivery | Blocked | Push of `1b3273a` to the configured Zeus origin failed with GitHub `Repository not found`; GIT-001 remains open and no remote/global identity was changed. |

## Phase Plan

| Phase | Scope | Status | Exit evidence |
| --- | --- | --- | --- |
| 0 | Inventory, baseline, tracker, decisions, and audit tooling | verified | Inventory validator, baseline evidence, all files classified. |
| 1 | Flutter/Dart pin, dependency resolution, analysis, generation, fonts, CI, and platform baseline | verified | Clean format/analyze/test/doc plus iOS and Android compile. |
| 2 | Domain architecture, SDK lifecycle, repositories, models, error/result policy, networking, storage, and security | verified | Unit/contract/fault tests, real platform storage tests, and both platform builds pass at `1b3273a`. |
| 3 | Design system and shared UX systems | fixing | Token audit, accessibility/widget/golden tests, reduced-motion behavior. |
| 4 | Onboarding and settings | unreviewed | Create/import/restart/unit/advanced end-to-end evidence. |
| 5 | Home, send, receive, swap, activity, and transaction details | unreviewed | Truthful four-rail flows and integration/widget evidence. |
| 6 | Documentation, performance, memory, platform hardening, and release evidence | unreviewed | Exact-candidate release report with measurements and constraints. |
| 7 | Independent file-by-file closeout | unreviewed | Zero unreviewed files and zero untracked non-accepted findings. |

## Findings

| ID | Severity | Area | Status | Finding | Evidence | Fix commit | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BASE-001 | P0 | Toolchain | verified | Flutter 3.38.9 / Dart 3.10.8 could not consume the SDK, which requires Flutter 3.41+ / Dart 3.11+. | `.fvmrc`, `pubspec.yaml`, SDK `pubspec.yaml` | `8e97370` | Flutter 3.44.9 / Dart 3.12.2 gates and both platform builds pass. |
| SDK-001 | P0 | Integration | verified | The immutable public `rgb_sdk_flutter` dependency needs one app-owned `UtexoWallet` owner and a DTO-isolating repository adapter. | `pubspec.yaml`; SDK import and ownership audit | `1b3273a` | SDK imports are restricted to `RgbWalletEngine` and typed failure mapping; runtime/repository tests and both platform builds pass. |
| DATA-001 | P0 | Product truth | unreviewed | Production UI presents static/mock balances, prices, activity, wallet identifiers, addresses, and delayed loading behavior. | Baseline runtime and source search | - | - |
| SEND-001 | P0 | Send | unreviewed | Send opens directly on a form prefilled with a sample Bitcoin address and has no asset/rail selection or real submission. | Baseline Send screenshot | - | - |
| ONB-001 | P0 | Onboarding | unreviewed | Create is not implemented; import is not backed by BIP39/SDK lifecycle behavior and exposes incomplete semantics. | Baseline Welcome/Import screenshots and accessibility snapshot | - | - |
| LIFE-001 | P0 | Lifecycle | verified | No single serialized owner existed for native wallet init, unlock, sync, reinit, shutdown, and destroy. | Source inventory and fault-path review | `1b3273a` | One injectable `WalletRuntime` serializes every native lifecycle and operation path; concurrency, reinit, rollback, disposal, and retry tests pass. |
| SEC-001 | P0 | Logging | verified | The unused HTTP logging interceptor could emit request/response bodies and sensitive native/network material. | `lib/core/network/interceptors/logging_interceptor.dart` | `8e97370` | Dead Chopper/interceptor surface and dependencies removed; repository search and fatal analysis pass. A production logging policy is still required in Phase 2. |
| PLAT-001 | P0 | Platform identity | blocked | Android/iOS use `com.example` identifiers and Android release uses debug signing. | Platform build files; DEC-006 | - | - |
| TEST-001 | P0 | Testing | fixing | Baseline had only two token assertions and no behavioral, platform, integration, accessibility, golden, lifecycle, or performance coverage. | Baseline and Phase 2 test runs | `1b3273a` | 137 host tests pass with 34.64% line coverage plus two real tests on each platform. UI, accessibility, golden, end-to-end, and measured performance coverage remains open. |
| BUILD-001 | P1 | Android | verified | Baseline Android build could not download Gradle and therefore did not compile. | Baseline `flutter build apk --debug` timeout | `8e97370` | Exact current-candidate x86_64 debug APK packages successfully; artifact hash is recorded above. |
| DOC-001 | P1 | Documentation | unreviewed | Architecture and setup material describe Aster/GDK/Boltz/Liquid-era concepts instead of the target UTEXO SDK architecture. | `README.md`, `docs/architecture/` | - | - |
| DOC-002 | P2 | API docs | verified | `dart doc` emitted two unresolved `[enableLogging]` references. | Baseline dartdoc output | `8e97370` | `dart doc --validate-links` completes with zero warnings and zero errors. |
| DOC-003 | P1 | Development setup | verified | Development instructions described removed import tools, non-fatal analysis, Flutter 3.38, and referenced no SDK override contract. | `docs/DEVELOPMENT.md`; `pubspec.yaml` comment | `8e97370` | Guide now matches executable Make/CI gates and documents a non-committed local SDK override. |
| DEP-001 | P1 | Dependencies | verified | Direct constraints were stale, `intl` was unconstrained, and unused architecture packages remained direct dependencies. | Baseline `flutter pub outdated`; consumer searches | `8e97370` | Direct dependencies were deliberately upgraded or removed; compatibility pins are recorded in DEC-007 and DEC-008. |
| DEP-002 | P2 | SDK dependency graph | blocked | Discontinued transitive package `js` 0.7.2 remains through `pointycastle` 3.9.1, which is constrained by the immutable SDK dependency. | `flutter pub deps`; SDK `pubspec.yaml` | - | Requires a future SDK revision that supports pointycastle 4 or removes that dependency; do not override the pinned SDK graph in the app. |
| FLAG-001 | P2 | Assets/dependencies | unreviewed | `circle_flags`, `country_flags`, and `flag` coexist despite one required flag implementation. | `pubspec.yaml` and settings/send imports | - | - |
| FONT-001 | P1 | Determinism | verified | UI typography relied on `google_fonts` rather than bundled exact DM Sans and Public Sans assets. | Theme source and `pubspec.yaml` | `8e97370` | Exact variable fonts and OFL licenses are bundled with recorded provenance/checksums; iOS and Android builds pass offline font registration. |
| NET-001 | P1 | Reliability | verified | The network layer lacked a uniform timeout, idempotent retry/backoff, failure taxonomy, and safe observability policy. | `lib/core/network/`; transport fault tests | `1b3273a` | Abortable GET-only retries run under one monotonic budget with bounded backoff/jitter, `Retry-After`, body limits, and redacted typed failures; all fault tests pass. |
| UX-001 | P1 | Shared UX | fixing | Haptics are called directly from widgets with repeated capability probes and no semantic/testable policy owner. | Six direct plugin call sites plus `CustomButton`; DEC-020 | - | Implement the semantic service, migrate every call site, and add capability/failure/intent tests. |
| UX-002 | P1 | Shared UX | fixing | Toasts are not owned by a queued/deduplicated service and scan uses `SnackBar`; settings uses fake success/failure demonstrations. | Toast/SnackBar search; DEC-021 | - | Replace with bounded queued presentation; fake outcomes must become truthful info/unavailable states or be removed. |
| ACCESS-001 | P1 | Accessibility | unreviewed | Baseline semantics include empty/duplicated labels and omit editable mnemonic fields. | Xcode runtime accessibility snapshots | - | - |
| ROUTE-001 | P1 | Routing | unreviewed | Current routes do not model asset/rail flow state or transaction details by stable ID. | Routing source inventory | - | - |
| HOME-001 | P1 | Home | unreviewed | The visibility control is not wired or persisted; asset rows do not represent BTC/RGB aggregate balances from real data. | Baseline Home and source | - | - |
| RECV-001 | P1 | Receive | unreviewed | Receive has no asset/rail selection or real invoice lifecycle and includes obsolete Direct Peg In behavior. | Baseline Receive and source | - | - |
| SWAP-001 | P1 | Swap | unreviewed | Swap assets do not match the target domain and execution must be made explicitly unavailable without simulating success. | Swap source; CON-002 | - | - |
| TX-001 | P1 | Activity | unreviewed | There is no normalized cross-rail activity model or transaction-details route/screen. | Transaction source inventory | - | - |
| SETTINGS-001 | P1 | Settings | unreviewed | Bitcoin unit and required advanced wallet/network settings are absent or placeholders. | Baseline Settings and source | - | - |
| SAFE-001 | P2 | Layout | fixing | Safe-area helpers live in spacing, mix `padding` and `viewPadding` behind ambiguous `Raw` names, and several forms/sheets manually pad where `SafeArea` should own keyboard-aware behavior. | Insets and SafeArea call-site audit; DEC-019 | - | Introduce typed window insets, migrate every helper call, prevent double padding, and test keyboard-open/closed semantics. |
| PERF-001 | P1 | Performance | unreviewed | No measured launch, frame, memory, leak, rebuild, cache, or SDK-handle baseline exists. | Test/tooling inventory | - | - |
| SEC-002 | P0 | Seed security | verified | Two hardcoded 12-word mnemonics were compiled into the app, printed around migration activity, and written to secure storage at startup. | `lib/core/utils/wallet_migration_service.dart`; `lib/main.dart` | `8e97370` | Migration and startup writes removed; repository search contains no mnemonic fixture or logging path. |
| SEC-003 | P0 | Seed privacy | verified | Legacy wallet identity and display name were deterministically derived directly from mnemonic text, creating a stable seed fingerprint outside the SDK lifecycle. | `wallet_id_generator.dart`; legacy `wallet_model.dart` | `8e97370` | Seed-derived generator removed; replacement `WalletProfile` accepts only an opaque post-SDK wallet ID and non-secret metadata. |
| GIT-001 | P1 | Delivery | blocked | Repository-local Zeus commits succeed, but the active host credential is not authorized for origin and GitHub returns `Repository not found`. | Pushes of `163a3cf`, `8e97370`, and `1b3273a` | - | Restore project-scoped Zeus access; do not change global identity or remote. |
| BUILD-002 | P1 | Code generation | verified | The original Riverpod 2.4 generator used analyzer 6.4, which only understood Dart 3.4 while the app now uses Dart 3.12. | Baseline Phase 1 build-runner warning | `8e97370` | Riverpod 3.3.2 / generator 4.0.4 resolves analyzer 12.1; generation completes without a language-version warning. |
| ARCH-001 | P1 | Networking/DI | verified | Unused Chopper clients, duplicate interceptors, and no-op DI modules exposed stale APIs and an unsafe body logger. | Consumer search found definitions only | `8e97370` | Removed the dead Chopper surface and dependency; fatal analyzer is clean. |
| PLAT-002 | P2 | Android toolchain | blocked | Flutter 3.44 warns that the app and `haptic_feedback`, `mobile_scanner`, and `rgb_sdk_flutter` apply the legacy Kotlin Gradle plugin, which a future Flutter release will reject. | Exact Android build output | - | App migration requires Flutter 3.47+; plugin owners must also publish built-in Kotlin support. Current AGP 9.0.1/Kotlin 2.3.20 build passes with Flutter-generated compatibility flags. |
| SDK-002 | P2 | iOS packaging | blocked | The pinned `rgb_sdk_flutter` revision does not support Swift Package Manager, which Flutter warns will become mandatory in a future release. | Exact iOS simulator build output | - | CocoaPods integration passes now; resolve in a future immutable SDK revision before Flutter removes fallback support. |
| TOOL-001 | P2 | Build environment | verified | Host disk exhaustion interrupted the first exact Android APK packaging attempt after compilation. | `:app:packageDebug` `No space left on device` | - | Removed only disposable caches and local build output; identical candidate build passed without touching protected regtest, simulator/emulator, source, or user data. |
| TOOL-002 | P3 | iOS simulator | blocked | iOS 26.5 logs duplicate `UIAccessibilityLoaderWebShared` implementations from its WebCore and WebKit accessibility bundles during launch. | Exact Phase 1 runtime log for process 45978 | - | This originates inside the Apple simulator runtime, not the app bundle. Recheck on a future simulator runtime and physical device; no app exception accompanied it. |
| SEC-004 | P0 | Error privacy | fixing | Route errors and generic HTTP/exception handling could expose raw exception strings or response bodies to users and diagnostics. | `app_router.dart`; removed `error_handler.dart`; failure tests; `scan_camera.dart` | - | Phase 2 route, transport, SDK, storage, and bootstrap paths expose stable redacted messages/codes only. Scanner UI still renders `error.toString()` and must be normalized in the Phase 3/5 UI audit before this finding can close. |
| LIFE-002 | P0 | Bootstrap | verified | App initialization had no typed failure state or recovery path; an exception could leave a blank app under an indefinitely visible splash. | `app_loader.dart::_load`; widget retry test | `1b3273a` | Startup has explicit typed failure/retry UI, unknown-outcome protection, timer cancellation, and deterministic container/runtime cleanup; widget and fault tests pass. |
| ARCH-002 | P1 | MVVM boundary | verified | `PriceCard` called a static HTTP service directly and owned request state, violating View -> ViewModel -> Repository/service flow and preventing injection. | Removed `bitcoin_price_service.dart`; repository tests | `1b3273a` | An injected repository and generated AsyncNotifier own the request; the widget renders truthful loading/unavailable/retry states and tests pass. |
| WALLET-001 | P0 | Wallet metadata | verified | The temporary SharedPreferences wallet registry used unsynchronized read-modify-write operations and did not integrate corruption recovery or native lifecycle transactions. | `wallet_repository.dart`; storage/repository fault tests | `1b3273a` | A serialized v3 journal and staged provisioning transaction handle corruption, uncertain commits, rollback, and startup reconciliation; fault matrix passes. |
| DOMAIN-001 | P0 | Asset model | fixing | `AssetModel` still represents asset and chain with display strings and cannot model Bitcoin/RGB USDT independently from onchain/Lightning rail and blockchain environment. | `asset_model.dart`; send/receive/swap call sites | `1b3273a` | App-owned asset ID, rail, network, and integer amount types are verified. Legacy feature UI must migrate to them in Phases 4/5 before this closes. |
| SEC-005 | P0 | Credential storage | verified | Secure storage used plugin defaults, including Android destructive reset-on-error, and had no versioned per-wallet credential contract. | `secure_storage_service.dart`; plugin 10.3.1 option audit; fault tests | `1b3273a` | Device-only/non-sync iOS storage, namespaced Android AES-GCM, reset-on-error disabled, and ownership-bound records pass host and real platform tests. |
| CONFIG-001 | P0 | Runtime configuration | verified | Wallet network/endpoints were not modeled or validated, so a build could mix environment, LSP, indexer, and RGB transport concepts. | Configuration source and validation tests | `1b3273a` | App/SDK network identity, service-specific schemes, loopback policy, and credential-bearing endpoint rejection are validated before native creation; tests pass. |
| LIFE-003 | P0 | Lifecycle transaction | verified | App lifecycle calls bypassed the repository mutation queue, and a failed shutdown could not reconcile the in-memory native owner with the durable active profile. | `main.dart`; `WalletRepository`; shutdown fault test | `1b3273a` | Lifecycle and metadata mutations share one repository queue; failed transitions reconcile from durable active state and fault tests pass. |
| SEC-006 | P0 | Provisioning rollback | verified | Interrupted provisioning and ID collisions could overwrite credentials or delete native resources whose ownership the current transaction could not prove. | Runtime/store fault matrix | `1b3273a` | Staged profiles and independent random ownership tokens bind secret and directory resources; collisions and ownership mismatch fail closed across the passing fault matrix. |
| STORE-001 | P0 | Upgrade safety | verified | The last committed app's metadata-only `wallet_registry_v1` would be ignored by the new v3 store and appear as an empty wallet list. | Storage-key history and migration regression | `1b3273a` | v1 is detected and preserved unchanged with explicit recovery-required failure; migration regression tests pass. |
| ARCH-003 | P1 | Domain layering | verified | Presentation imported persistence models and serialization lived in a UI-visible data model. | Import graph and deleted `data/models` files | `1b3273a` | Immutable app-owned profiles/registry live in domain while JSON remains inside the storage adapter; analyzer and import audit pass. |
| DOMAIN-002 | P1 | Native mapping | verified | Native network labels, balances, counters, public keys, and Lightning millisatoshis were not validated at the SDK boundary. | `RgbWalletEngine`; model and adapter tests | `1b3273a` | Adapter rejects mismatched/malformed native state, preserves integer units and signed pending deltas, and accounts for colored Bitcoin UTXO locks; tests pass. |
| NET-002 | P1 | Cancellation | verified | Whole-operation HTTP timeout did not abort an active request and could permit retries after the caller had timed out. | Abortable transport tests | `1b3273a` | `AbortableRequest` and one monotonic operation budget abort active I/O and prevent later attempts; timeout/cancellation tests pass. |
| DEP-003 | P2 | Dependency hygiene | verified | `connectivity_plus` and its provider abstraction were unused and could encourage treating reachability hints as request truth. | Consumer search and dependency graph | `1b3273a` | Package/provider removed; request-result-based reachability policy is documented and both platform builds pass. |
| PLAT-003 | P0 | Android backup | verified | Wallet databases, preferences, or encrypted storage could enter Android cloud backup or device transfer. | Android manifest and extraction rules | `1b3273a` | Release manifest has `allowBackup=false` and restrictive legacy/Android 12+ rules; platform tests and release build pass. |
| CONFIG-002 | P0 | RGB asset identity | blocked | No deployment-owned RGB USDT contract ID and precision are configured, so the app cannot truthfully identify or aggregate USDT on any target environment. | Product requirements and app configuration audit | - | Requires an environment-specific immutable contract ID/precision source before Phase 5 integration. Never infer identity from ticker text. |
| SEC-007 | P0 | User authentication | blocked | The product has not decided whether viewing a seed, exporting xpubs, or reopening wallet credentials requires device authentication, an app PIN, both, or neither. | Secure-storage and settings requirements | - | A product/security decision is required before those screens can be release-qualified; storage contracts are designed to accept a later user-presence policy. |
| STORE-002 | P0 | Upgrade safety | verified | A failed legacy-seed preflight could be cached as complete and silently bypassed on a later retry. | `legacy_wallet_seed_preflight.dart`; repeated-failure tests | `1b3273a` | The guard rechecks until it observes an authoritative empty source; failure and late-seed tests pass. |
| STORE-003 | P0 | Metadata durability | verified | A single mutable metadata document could lose the wallet registry during a torn write or corrupt replacement. | `wallet_registry_document_store.dart`; corruption/torn-write tests | `1b3273a` | The checksummed, generation-numbered two-slot journal recovers the newest valid document and fsyncs atomic replacement; fault tests pass. |
| STORE-004 | P0 | Reconciliation | verified | Durable profile state, secure credentials, and native directories could diverge after interruption without deterministic recovery rules. | `wallet_profile_store.dart`; `wallet_repository.dart`; reconciliation matrix | `1b3273a` | Bootstrap reconciles staged/ready/quarantined profiles by ownership token, preserves uncertain material, and only removes proven-owned resources; the matrix passes. |
| STORE-005 | P0 | Data preservation | verified | Unknown or future durable profile states could be discarded by an older app. | Registry decoding and compatibility tests | `1b3273a` | Unknown committed records are quarantined and preserved; compatibility tests pass. |
| STORE-006 | P0 | Legacy precedence | verified | A current empty/corrupt registry could mask recoverable legacy metadata. | Registry fallback tests | `1b3273a` | Legacy metadata is checked independently and cannot be hidden by a current journal; regressions pass. |
| STORE-007 | P2 | Metadata semantics | verified | `updatedAt` could remain equal to profile creation time after a durable provisioning commit. | `wallet_profile_store.dart`; injected-clock tests | `1b3273a` | Injected monotonic commit time advances when provisioning becomes durable; tests pass. |
| PLAT-004 | P0 | Native storage | verified | Dart APIs alone could not prove wallet directory/file ownership modes, symlink ancestry, backup exclusion, atomic replacement, and durable directory sync. | `AppDelegate.swift`; `MainActivity.kt`; platform integration tests | `1b3273a` | Native bridges validate ancestry, reject symlinks, apply owner-only modes, perform bounded off-main I/O, atomically replace files, fsync parents, and apply iOS protection/no-backup; both platform tests pass. |
| TEST-002 | P0 | Platform storage | verified | Secure-storage namespace and native wallet-file policy had no real iOS or Android execution proof. | `integration_test/wallet_storage_security_test.dart`; simulator/emulator logs | `1b3273a` | Both tests pass on iPhone Air / iOS 26.5 and Utexo_API_36 / Android 16/API 36. |
| LIFE-004 | P1 | Timeout ownership | verified | Adding a Dart timeout around an uncancellable native mutation could release the app queue while native work continued. | SDK timeout contract review; `wallet_runtime.dart` | `1b3273a` | Native calls remain serialized until SDK futures settle and rely on SDK typed timeout/quarantine; app-owned HTTP uses cancellable budgets. Runtime and timeout tests pass. |
| LIFE-005 | P1 | Teardown | verified | Provider and widget disposal callbacks are synchronous and cannot by themselves prove awaited native cleanup. | `app_bootstrap.dart`; `app_loader.dart`; `main.dart`; fault tests | `1b3273a` | Bootstrap failure and authoritative lifecycle paths await repository cleanup; provider teardown is only a best-effort fallback. Fault tests pass. |
| DATA-002 | P0 | Market truth | verified | The home chart fabricated candle high/low values and the price service could not expose provenance, freshness, or truthful unavailable state. | Removed `bitcoin_price_service.dart`; market repository/view-model tests | `1b3273a` | CoinGecko responses become validated integer cents/basis points with source timestamps; no synthetic values or success fallback remain and repository/ViewModel tests pass. |
| NET-003 | P1 | Transport hardening | verified | App-owned HTTP accepted broad response behavior without a strict redirect, scheme, body-size, and diagnostic redaction contract. | `resilient_http_client.dart`; transport fault tests | `1b3273a` | HTTPS policy, disabled redirects, bounded bodies, `Retry-After`, and redacted failures pass adversarial tests. |
| CONFIG-003 | P0 | Regtest isolation | verified | App configuration could point at the protected `rgb-lightning-node-perf-lab` ports. | `app_environment.dart`; configuration tests; DEC-005 | `1b3273a` | Protected ports are rejected on loopback and Android emulator host aliases; configuration tests pass without touching the existing stack. |
| SEC-008 | P0 | Diagnostic bounds | verified | Typed failures could retain unbounded or sensitive native/transport payloads through diagnostic causes. | `failure_mapper.dart`; adversarial redaction tests | `1b3273a` | User messages/codes and diagnostics are allow-listed and bounded; raw bodies, headers, URIs, and native messages are excluded by passing tests. |
| SEC-009 | P0 | Mnemonic ingress | verified | A malformed SDK mnemonic response could enter onboarding or persistence as trusted recovery material. | `wallet_repository.dart`; mnemonic postcondition tests | `1b3273a` | Generation is serialized, normalized, and rejected unless the SDK returns exactly 12 non-empty words; tests pass. BIP39 checksum UX remains ONB-001. |
| DEP-004 | P1 | Release assets | verified | The first Android release build exposed an unbundled Cupertino icon font reachable through Flutter framework code. | Initial release build warning; `pubspec.yaml`; rebuilt APK | `1b3273a` | `cupertino_icons` 1.0.9 is explicitly bundled and the exact release build reports successful tree shaking instead of a missing font. |
| PLAT-005 | P1 | Android compilation | verified | The first native policy implementation called unavailable `android.system.Os.rmdir`, breaking Kotlin compilation. | Android integration build failure and corrected bridge | `1b3273a` | Cleanup verifies an empty owned directory and uses checked `File.delete()` with bounded error mapping; Android integration and release builds pass. |
| TOOL-003 | P2 | Physical iOS evidence | blocked | The app built and installed on a connected iPhone, but Flutter could not attach to the VM service over the wireless/local-network path. | Device `00008130-000A552C3EBA001C` run log | - | This does not invalidate simulator/native test evidence, but physical iOS runtime, haptic, performance, and memory evidence remains required in Phase 6. |
| DOC-004 | P1 | Documentation gate | fixing | Reusing the ignored default `doc/api` output retained obsolete pages and produced 217 false stale-file warnings. | First Phase 2 dartdoc run versus fresh-output rerun | - | A fresh isolated output produced 178 libraries with zero warnings/errors. Phase 6 must make that clean-output behavior part of the repeatable release command and CI/documentation contract. |
| DS-001 | P1 | Shape system | fixing | Material theme components and several shared/feature surfaces use `RoundedRectangleBorder`, `BoxDecoration`, or `ClipRRect` where the product contract requires a squircle; pill controls are not modeled separately. | `app_theme.dart`; bottom nav; bottom sheets; button audit | - | Introduce one explicit squircle-versus-pill component policy and migrate every audited surface without changing color values. |
| DS-002 | P1 | Numeric typography | fixing | `NumericText` applies Public Sans to the entire string and numeric chunking includes `$` and `%`, so symbols/units can receive the numeric font. A null style also fails to apply Public Sans at all. | `amount_text.dart`; all numeric call sites | - | Both helpers must style only digit/separator/sign spans from the resolved inherited style; currency symbols, units, labels, and asset names remain DM Sans. |
| DS-003 | P1 | Theme integrity | fixing | `ThemeContext` silently constructs fallback extensions when the app theme is incomplete, masking missing token registration and creating inconsistent component output. | `theme_context.dart`; bootstrap theme ownership | - | Ensure every app/bootstrap surface is under `AppTheme.light()` and fail fast when a required extension is absent. |
| DS-004 | P2 | Component recipes | fixing | Loader and chart visual recipes still expose or embed reusable sizes, alpha values, and transition geometry outside their owning metric/effect/art systems. | `grid_loader.dart`; `candle_chart.dart`; splash art | - | Move repeatable component/art decisions to semantic metric/effect/art tokens; retain only mathematical interpolation local to painters. |
| MOTION-001 | P1 | Reduced motion | fixing | Looping loaders, shimmer, chart choreography, splash, button scale, nav motion, toast motion, and swap choreography ignore the platform's disable-animation preference. | Animation-controller and implicit-animation audit | - | Add one effective-duration/reduced-motion policy; decorative loops stop on a stable frame and state transitions complete without timers when motion is disabled. |
| MOTION-002 | P1 | Offscreen work | fixing | `IndexedStack` keeps feature screens mounted without explicitly muting their tickers, allowing hidden charts/animations to consume resources. | `skeleton_screen.dart`; ticker audit | - | Wrap each tab in active-state `TickerMode` and verify hidden screens cannot animate or receive interaction. |
| ACCESS-002 | P1 | Interactive controls | fixing | Shared tap surfaces rely on `GestureDetector`, omit keyboard/focus behavior, can duplicate semantics, and do not consistently expose loading/dismiss state. | `custom_button.dart`; app bar; bottom nav; toast; selection rows | - | Normalize focus/keyboard/touch targets/semantics and add widget/accessibility tests. |
| UX-003 | P1 | Button behavior | fixing | `CustomButton` fires haptics on pointer-down before an accepted tap, probes capability per press, and has no semantic commit/navigation intent. | `custom_button.dart`; haptic call sites | - | Trigger one semantic haptic only for an accepted enabled action; loading remains size-stable, blocks duplicates, and is announced. |
| UX-004 | P2 | Selection choreography | fixing | Wallet and asset selection insert a fixed post-success delay before navigation, even under reduced motion, and can leave context-owned timers outside a single choreography policy. | wallet selection; asset selector sheet | - | Resolve or remove commit delay through the motion policy and navigate only after actual selection success. |
| ARCH-004 | P1 | Plugin boundary | unreviewed | Scan presentation constructs `ImagePicker` and `MobileScannerController` directly, contrary to the View -> ViewModel -> repository/service boundary. | scan screen/widget import audit | - | Move plugin ownership behind an injectable scanner/media service during the scan/send integration phase; do not hide the gap in Phase 3. |
| NAV-001 | P1 | Bottom navigation | fixing | The second bottom-nav item is announced as “Cards” with a card icon while it opens Scan, and the floating nav ignores the persistent bottom hardware inset. | `bottom_nav.dart`; `skeleton_index_provider.dart` | - | Use the correct Scan label/icon, semantic selection haptic, squircle surface, and explicit bottom-system-inset geometry. |

## Generated Artifact Validation

These files are generated or resolved artifacts and are intentionally excluded
from the hand-review inventory. They must be regenerated or resolved and diffed
through their owning tool.

| Artifact | Owner | Status | Verification |
| --- | --- | --- | --- |
| `pubspec.lock` | Flutter pub | verified | Resolves on Flutter 3.44.9; SDK resolved-ref and dependency graph reviewed; both platform builds pass. |
| `ios/Podfile.lock` | CocoaPods / Flutter | verified | Regenerated for the pinned SDK and deployment target; exact simulator build and launch pass. |
| `**/*.g.dart` | build_runner generators | verified | Generated files remain ignored and reproducible; generation, fatal analysis, and tests pass. |
| `ios/.spm.pods/**` | CocoaPods SwiftPM bridge | verified | Flutter/CocoaPods generated cache remains ignored and is recreated by the toolchain; it is not hand-edited or committed. |

## File Review Inventory

The inventory is mechanically checked by
`dart run tool/verify_production_tracker.dart`. Findings still require a real
line-by-line review; inventory synchronization is not evidence of correctness.

<!-- FILE_INVENTORY_START -->
| File | Kind | Status | Finding IDs | Verification | Fix commit |
| --- | --- | --- | --- | --- | --- |
| `.envrc` | Project configuration | unreviewed | - | - | - |
| `.fvmrc` | Project configuration | verified | BASE-001 | Flutter 3.44.9 installed and all Phase 1 gates pass | `8e97370` |
| `.github/workflows/dart.yml` | CI | verified | BASE-001, BUILD-002 | Pinned toolchain, generation, fatal analysis, tests, and tracker gates reviewed | `8e97370` |
| `.gitignore` | Project configuration | unreviewed | - | - | - |
| `.metadata` | Project configuration | verified | BASE-001 | Flutter migration metadata matches framework revision `6b182d2c` and owned platforms | `8e97370` |
| `.vscode/settings.json` | Project configuration | verified | BASE-001 | Project-local Flutter SDK path points to 3.44.9 | `8e97370` |
| `Makefile` | Project configuration | verified | BUILD-002 | Commands executed locally; lint target is non-mutating and passes | `8e97370` |
| `README.md` | Project configuration | fixing | DOC-001 | Broken dartdoc-style local links removed; product rewrite remains in Phase 6 | `8e97370` |
| `analysis_options.yaml` | Project configuration | verified | BUILD-002, ARCH-001 | Strict inference/casts/raw types and lifecycle/future/security lints pass with zero diagnostics | `8e97370` |
| `android/.gitignore` | Android platform | unreviewed | - | - | - |
| `android/app/build.gradle.kts` | Android platform | fixing | BUILD-001, PLAT-001, PLAT-002 | AGP 9 / Java 17 / SDK 36 x86_64 APK build passes; release identity/signing and future Kotlin migration remain open | `8e97370` |
| `android/app/src/debug/AndroidManifest.xml` | Android platform | verified | CONFIG-001 | Debug cleartext policy is explicit and limited to development builds; merged release manifest remains cleartext-disabled | `1b3273a` |
| `android/app/src/main/AndroidManifest.xml` | Android platform | fixing | PLAT-001, PLAT-003 | Backup/transfer and cleartext policy verified in merged release manifest; application identity/name remain blocked | `1b3273a` |
| `android/app/src/main/kotlin/com/example/asterdev/MainActivity.kt` | Android platform | verified | PLAT-004, PLAT-005 | Native policy bridge reviewed; Android integration tests and release compilation pass | `1b3273a` |
| `android/app/src/main/res/drawable-v21/launch_background.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/drawable/launch_background.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/values-night/styles.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/values/styles.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/xml/backup_rules.xml` | Android platform | verified | PLAT-003 | Every application data domain excluded; merged release manifest references the rule | `1b3273a` |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | Android platform | verified | PLAT-003 | Cloud backup and device-transfer exclusions cover every application data domain | `1b3273a` |
| `android/app/src/profile/AndroidManifest.xml` | Android platform | verified | CONFIG-001 | Profile cleartext policy is explicit; release remains disabled | `1b3273a` |
| `android/build.gradle.kts` | Android platform | unreviewed | - | - | - |
| `android/gradle.properties` | Android platform | fixing | PLAT-002 | Flutter-generated AGP 9 compatibility flags build; built-in Kotlin migration remains blocked on toolchain/plugins | `8e97370` |
| `android/gradle/wrapper/gradle-wrapper.properties` | Android platform | verified | BUILD-001 | Gradle 9.1.0 matches Flutter 3.44 template and packages exact APK | `8e97370` |
| `android/settings.gradle.kts` | Android platform | fixing | BUILD-001, PLAT-002 | AGP 9.0.1/Kotlin 2.3.20 compile; future built-in Kotlin migration tracked | `8e97370` |
| `assets/brand/aster-logo.svg` | Asset | unreviewed | - | - | - |
| `assets/brand/banner.svg` | Asset | unreviewed | - | - | - |
| `assets/data/countries.json` | Asset | unreviewed | - | - | - |
| `assets/data/currencies.json` | Asset | unreviewed | - | - | - |
| `assets/fonts/DMSans-Italic-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | `8e97370` |
| `assets/fonts/DMSans-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | `8e97370` |
| `assets/fonts/LICENSE-DM-SANS.txt` | Asset | verified | FONT-001 | Upstream OFL license bundled and reviewed | `8e97370` |
| `assets/fonts/LICENSE-PUBLIC-SANS.txt` | Asset | verified | FONT-001 | Upstream OFL license bundled and reviewed | `8e97370` |
| `assets/fonts/PublicSans-Italic-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | `8e97370` |
| `assets/fonts/PublicSans-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | `8e97370` |
| `assets/fonts/README.md` | Asset | verified | FONT-001 | Source commit, role ownership, hashes, and replacement policy reviewed | `8e97370` |
| `assets/icons/images/bitcoin.png` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/btc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/lbtc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdt.svg` | Asset | unreviewed | - | - | - |
| `assets/texture/noise.jpg` | Asset | unreviewed | - | - | - |
| `assets/texture/shape.png` | Asset | unreviewed | - | - | - |
| `devtools_options.yaml` | Project configuration | unreviewed | - | - | - |
| `docs/DEVELOPMENT.md` | Documentation | verified | DOC-003, CONFIG-003 | Commands, toolchain, SDK override, compile-time service configuration, and protected-regtest isolation match executable policy | `1b3273a` |
| `docs/PRODUCTION_REFACTOR_TRACKER.md` | Documentation | verified | - | Inventory validator, Phase 1/2 evidence reconciliation, and Markdown review | `1b3273a` |
| `docs/architecture/ARCHITECTURE_GOOGLE_STYLE.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/ARCHITECTURE_SUMMARY.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/BARREL_EXPORTS.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/NETWORK_RELIABILITY.md` | Documentation | verified | NET-001, NET-002, NET-003, LIFE-004 | Retry, timeout, cancellation, reachability, mutation, and native-timeout ownership match implementation/tests | `1b3273a` |
| `docs/architecture/SDK_INTEGRATION.md` | Documentation | verified | SDK-001, DOC-003, LIFE-001, CONFIG-003 | Immutable pin, local override, runtime ownership, adapter boundary, lifecycle, and isolated regtest policy match implementation | `1b3273a` |
| `docs/design/DESIGN_SYSTEM_NORMALIZATION_TRACKER.md` | Documentation | unreviewed | - | - | - |
| `docs/design/DOCSTRING_PATTERNS.md` | Documentation | unreviewed | - | - | - |
| `docs/design/HAPTIC_FEEDBACK.md` | Documentation | unreviewed | - | - | - |
| `docs/design/PRESENTATION_SYSTEMS.md` | Documentation | unreviewed | - | - | - |
| `docs/design/TYPOGRAPHY_USAGE.md` | Documentation | unreviewed | - | - | - |
| `docs/release/evidence/baseline/ios-home-bbbc315.jpg` | Documentation | reviewed-clean | HOME-001, DATA-001 | Captured from exact baseline commit on iPhone Air | `163a3cf` |
| `docs/release/evidence/baseline/ios-import-bbbc315.jpg` | Documentation | reviewed-clean | ONB-001, ACCESS-001 | Captured from exact baseline commit on iPhone Air | `163a3cf` |
| `docs/release/evidence/baseline/ios-receive-bbbc315.jpg` | Documentation | reviewed-clean | RECV-001 | Captured from exact baseline commit on iPhone Air | `163a3cf` |
| `docs/release/evidence/baseline/ios-send-bbbc315.jpg` | Documentation | reviewed-clean | SEND-001, DATA-001 | Captured from exact baseline commit on iPhone Air | `163a3cf` |
| `docs/release/evidence/baseline/ios-welcome-bbbc315.jpg` | Documentation | reviewed-clean | ONB-001 | Captured from exact baseline commit on iPhone Air | `163a3cf` |
| `flake.lock` | Project configuration | unreviewed | - | - | - |
| `flake.nix` | Project configuration | unreviewed | - | - | - |
| `integration_test/wallet_storage_security_test.dart` | Test | verified | TEST-002, SEC-005, PLAT-004 | Both cases pass on iOS 26.5 simulator and Android 16/API 36 emulator | `1b3273a` |
| `ios/.gitignore` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/AppFrameworkInfo.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/Debug.xcconfig` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/Profile.xcconfig` | iOS platform | verified | SDK-001 | Profile configuration inherits CocoaPods and Flutter generated settings consistently | `1b3273a` |
| `ios/Flutter/Release.xcconfig` | iOS platform | unreviewed | - | - | - |
| `ios/Podfile` | iOS platform | fixing | SDK-001, SDK-002, PLAT-001 | SDK-required iOS 18.5 deployment passes exact simulator build; identity and future SwiftPM support remain open | `8e97370` |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS platform | fixing | SDK-001, SDK-002, PLAT-001 | Native storage bridge channels and profile configuration compile; identity and future SDK SwiftPM support remain unresolved | `1b3273a` |
| `ios/Runner.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | iOS platform | verified | SDK-002 | Flutter-generated prepare-framework action reviewed; CocoaPods simulator build passes | `8e97370` |
| `ios/Runner.xcworkspace/contents.xcworkspacedata` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/AppDelegate.swift` | iOS platform | verified | PLAT-004 | Native policy bridge reviewed; iOS integration tests and exact simulator build pass | `1b3273a` |
| `ios/Runner/Assets.xcassets/Contents.json` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Assets.xcassets/aster-logo.imageset/Contents.json` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Assets.xcassets/aster-logo.imageset/aster-logo.svg` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Assets.xcassets/background.imageset/Contents.json` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Assets.xcassets/background.imageset/background.svg` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/AsterIcon.icon/Assets/aster_logo.svg` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/AsterIcon.icon/icon.json` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Base.lproj/Main.storyboard` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Info.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Launch Screen.storyboard` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/Runner-Bridging-Header.h` | iOS platform | unreviewed | - | - | - |
| `ios/RunnerTests/RunnerTests.swift` | iOS platform | unreviewed | - | - | - |
| `lib/core/bootstrap/app_bootstrap.dart` | Dart source | verified | LIFE-002, LIFE-005 | Bootstrap ownership, unknown-outcome composition, awaited cleanup, and container disposal pass fault tests | `1b3273a` |
| `lib/core/bootstrap/app_loader.dart` | Dart source | verified | LIFE-002, LIFE-005 | Typed failure/retry, reveal timer cancellation, retry gating, and container disposal pass widget tests | `1b3273a` |
| `lib/core/config/app_environment.dart` | Dart source | verified | CONFIG-001, CONFIG-003 | Network/service validation, credential rejection, development schemes, and protected-port policy pass tests | `1b3273a` |
| `lib/core/config/config.dart` | Dart source | verified | CONFIG-001 | Boundary barrel exports only app configuration | `1b3273a` |
| `lib/core/constants/app_constants.dart` | Dart source | verified | NET-001 | Reusable timeout/page constants were removed in favor of owned semantic policies; remaining app identity constants reviewed | `1b3273a` |
| `lib/core/constants/constants.dart` | Dart source | verified | ARCH-001 | Barrel no longer exports removed endpoint surface | `1b3273a` |
| `lib/core/constants/storage_keys.dart` | Dart source | verified | STORE-001, SEC-005 | Only versioned, namespaced registry/credential and legacy-detection keys remain | `1b3273a` |
| `lib/core/core.dart` | Dart source | verified | CONFIG-001 | Core boundary exports reviewed after configuration/error/network normalization | `1b3273a` |
| `lib/core/di/di.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/providers.dart` | Dart source | verified | SDK-001, LIFE-001, LIFE-005 | One keep-alive runtime/repository owner, injectable dependencies, and teardown fallback pass provider tests | `1b3273a` |
| `lib/core/errors/app_failure.dart` | Dart source | verified | SEC-004, SEC-008 | Sealed typed failure contract, redacted UI fields, retryability, and unknown-outcome semantics reviewed/tested | `1b3273a` |
| `lib/core/errors/app_result.dart` | Dart source | verified | DEC-012 | Sealed success/failure result boundary reviewed and exercised across repositories/ViewModels | `1b3273a` |
| `lib/core/errors/errors.dart` | Dart source | verified | DEC-012 | Boundary barrel exports only the normalized error/result surface | `1b3273a` |
| `lib/core/errors/failure_mapper.dart` | Dart source | verified | SEC-004, SEC-008 | SDK/native/transport/storage taxonomy and bounded redaction pass adversarial tests | `1b3273a` |
| `lib/core/network/http_payload.dart` | Dart source | verified | NET-003 | Immutable bounded HTTP payload carrier reviewed/tested | `1b3273a` |
| `lib/core/network/network.dart` | Dart source | verified | NET-001, NET-002, NET-003 | Boundary barrel exports only normalized reliability primitives | `1b3273a` |
| `lib/core/network/network_cancellation.dart` | Dart source | verified | NET-002 | Idempotent cancellation signal and listener cleanup pass transport tests | `1b3273a` |
| `lib/core/network/network_timeout_policy.dart` | Dart source | verified | NET-001 | Explicit connect/receive/send/operation budgets validated through transport tests | `1b3273a` |
| `lib/core/network/resilient_http_client.dart` | Dart source | verified | NET-001, NET-002, NET-003, SEC-008 | Abort, deadline, retry, redirect, body-limit, classification, and redaction fault matrix passes | `1b3273a` |
| `lib/core/network/retry_policy.dart` | Dart source | verified | NET-001 | Bounded ordered delays, finite jitter, exponential backoff, and injected sleep/random paths pass tests | `1b3273a` |
| `lib/core/storage/preferences_service.dart` | Dart source | verified | ARCH-001, STORE-001 | Async persistence forwarding and registry ownership reviewed under journal tests | `1b3273a` |
| `lib/core/storage/secure_storage_service.dart` | Dart source | verified | SEC-005, TEST-002 | Explicit platform options and namespaced operations pass host and real iOS/Android round trips | `1b3273a` |
| `lib/core/storage/storage.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/extensions/string_extensions.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/formatters.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/utils.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/validators.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/data/bitcoin_market_repository.dart` | Dart source | verified | DATA-002, NET-001, NET-003 | Bounded CoinGecko mapping, integer conversion, chronology, freshness, fallback, and truthful failure tests pass | `1b3273a` |
| `lib/features/home/data/data.dart` | Dart source | verified | ARCH-002 | Data boundary exports repository and immutable market models only | `1b3273a` |
| `lib/features/home/data/models/bitcoin_market_snapshot.dart` | Dart source | verified | DATA-002 | Source/freshness/time/value invariants and value equality pass tests | `1b3273a` |
| `lib/features/home/data/models/chart_data_item.dart` | Dart source | verified | DATA-002 | Immutable chart point equality supports deterministic widget data-change detection | `1b3273a` |
| `lib/features/home/presentation/screens/home_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/view_model/bitcoin_market_view_model.dart` | Dart source | verified | ARCH-002, DATA-002 | Generated AsyncNotifier owns repository request and suppresses duplicate retry; tests pass | `1b3273a` |
| `lib/features/home/presentation/view_model/view_models.dart` | Dart source | verified | ARCH-002 | Feature-boundary barrel exports the market ViewModel only | `1b3273a` |
| `lib/features/home/presentation/widgets/asset_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/assets_section.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/candle_chart.dart` | Dart source | verified | DATA-002 | Fabricated candle extrema removed; real point updates/reset and animation ownership reviewed | `1b3273a` |
| `lib/features/home/presentation/widgets/home_action_buttons.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/home_header.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/mesh_gradient_background.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/price_card.dart` | Dart source | verified | ARCH-002, DATA-002 | Consumer widget renders injected loading/data/error/empty/retry states without direct I/O or synthetic success | `1b3273a` |
| `lib/features/home/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/screens/market_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/widgets/market_tile.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/screens/onboarding_import_wallet_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/screens/onboarding_welcome_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_header.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_icon_grid.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_mesh_background.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/screens/receive_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/screens/receive_set_amount_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/widgets/receive_card.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/screens/scan_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/scan_state.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/scan_view_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/view_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_background.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_camera.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_control_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_enter_address_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_frame.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_overlay_painter.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_wallet_header.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/screens/send_address_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/screens/send_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/widgets/send_address_card.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/widgets/send_card.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/send/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/screens/country_selection_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/screens/currency_selection_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/screens/settings_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/widgets/country_select_option_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/widgets/currency_select_option_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/widgets/settings_option_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/settings/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/providers/providers.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/providers/skeleton_index_provider.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/screens/skeleton_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/widgets/bottom_nav.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/screens/swap_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/widgets/asset_selector_sheet.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/widgets/swap_card.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/widgets/swap_pair.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/swap/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/transaction/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/transaction/presentation/screens/transaction_list_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/transaction/presentation/widgets/transaction_item.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/transaction/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/repository/repository.dart` | Dart source | verified | SDK-001 | Repository boundary barrel exports only the app-owned repository | `1b3273a` |
| `lib/features/wallet/data/repository/wallet_repository.dart` | Dart source | verified | SDK-001, LIFE-001, LIFE-003, LIFE-005, WALLET-001, STORE-004, SEC-006, SEC-009 | Serialized bootstrap/provision/switch/lifecycle/reconciliation and mnemonic postconditions pass the repository fault matrix | `1b3273a` |
| `lib/features/wallet/data/runtime/rgb_wallet_engine.dart` | Dart source | verified | SDK-001, DOMAIN-002 | Stable SDK adapter validates network, keys, counters, addresses, balances, units, and overflow; adapter tests pass | `1b3273a` |
| `lib/features/wallet/data/runtime/runtime.dart` | Dart source | verified | LIFE-001 | Runtime boundary exports only owned interfaces/implementation | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_directory_manager.dart` | Dart source | verified | PLAT-004, SEC-006 | Create/open/collision/rollback ownership semantics pass host and platform tests | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_engine.dart` | Dart source | verified | SDK-001, DOMAIN-002 | App-owned native adapter contract and typed result shapes reviewed/tested | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_identity_generator.dart` | Dart source | verified | SEC-003, SEC-006 | CSPRNG opaque IDs, independent ownership tokens, and 256-bit database secrets pass shape/independence tests | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_runtime.dart` | Dart source | verified | LIFE-001, LIFE-004, SEC-006, STORE-004 | Single serialization queue, state machine, rollback, quarantine, reinit, disposal, and audit fault matrix passes | `1b3273a` |
| `lib/features/wallet/data/storage/legacy_wallet_seed_preflight.dart` | Dart source | verified | STORE-001, STORE-002 | Legacy seed detection fails closed, preserves evidence, and rechecks non-authoritative outcomes; tests pass | `1b3273a` |
| `lib/features/wallet/data/storage/storage.dart` | Dart source | verified | WALLET-001 | Storage boundary exports reviewed ownership/journal/security contracts only | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_profile_store.dart` | Dart source | verified | WALLET-001, STORE-001, STORE-004, STORE-005, STORE-006, STORE-007 | Versioned decoding, serialized mutation, quarantine, legacy precedence, and monotonic timestamps pass tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_registry_document_store.dart` | Dart source | verified | STORE-003, PLAT-004 | Bounded checksummed two-slot journal and atomic native replacement pass corruption/torn-write tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_secret_store.dart` | Dart source | verified | SEC-005, SEC-006, SEC-009 | Versioned bounded credential envelope, ownership-aware commit/delete, corruption and unknown-outcome handling pass tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_storage_security.dart` | Dart source | verified | PLAT-004 | Typed platform-channel policy validates inputs and maps bounded native failures; real platform tests pass | `1b3273a` |
| `lib/features/wallet/domain/models/models.dart` | Dart source | verified | DEC-013 | Domain boundary exports only app-owned asset/network/amount/balance/profile/registry models | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_amount.dart` | Dart source | verified | DEC-013, DOMAIN-002 | Integer smallest-unit/rail/asset invariants and signed-64-bit bounds pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_asset.dart` | Dart source | verified | DEC-013 | Asset protocol/ID/precision are independent from rail and environment; validation/value tests pass | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_balance.dart` | Dart source | verified | DOMAIN-002 | Onchain/Lightning total, available, pending, locked, receivable dimensions use checked integer aggregation; tests pass | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_network.dart` | Dart source | verified | CONFIG-001, DOMAIN-002 | Network status and public-key bounds/value semantics pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_profile.dart` | Dart source | verified | ARCH-003, SEC-003 | Non-secret immutable metadata, Unicode control rejection, UTC timestamps, and opaque identity pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_registry.dart` | Dart source | verified | WALLET-001 | Immutable registry invariants, staged/ready/quarantined states, active selection, and equality pass tests | `1b3273a` |
| `lib/features/wallet/presentation/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/models/wallet_state.dart` | Dart source | verified | SDK-001, DEC-012 | Immutable operation-specific state carries domain profiles and typed operation failure; equality reviewed/tested | `1b3273a` |
| `lib/features/wallet/presentation/pages/pages.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | Dart source | verified | LIFE-003 | Selection navigates only after confirmed transactional switch; duplicate/selected interactions remain disabled | `1b3273a` |
| `lib/features/wallet/presentation/view_model/viewmodels.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/wallet_viewmodel.dart` | Dart source | verified | SDK-001, DEC-012, LIFE-003 | Generated AsyncNotifier exposes repository-backed load/switch state, suppresses overlap, and maps typed failures; tests pass | `1b3273a` |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | Dart source | verified | ARCH-003 | Widget consumes domain profile rather than persistence model; strict analysis passes | `1b3273a` |
| `lib/features/wallet/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/main.dart` | Dart source | verified | SEC-002, LIFE-001, LIFE-003, LIFE-005 | One bootstrapped container and serialized lifecycle tail own repository resume/suspend/dispose with redacted debug diagnostics | `1b3273a` |
| `lib/shared/feedback/feedback.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/feedback/feedback_scope.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/feedback/haptic_feedback_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/feedback/toast_controller.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/feedback/toast_host.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/feedback/toast_message.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/layout/layout.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/layout/window_insets.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/asset_model.dart` | Dart source | fixing | DOMAIN-001 | Existing model reviewed; typed asset/rail/environment replacement remains Phase 2 | - |
| `lib/shared/models/country_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/currency_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/motion/motion.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/motion/motion_policy.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/app_router.dart` | Dart source | fixing | ROUTE-001, SEC-004 | Raw route diagnostics removed and router disposal added; feature route modeling/guards remain Phase 5 | `1b3273a` |
| `lib/shared/routing/route_config.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/route_guards.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/route_names.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/route_paths.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/routing.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/screens/animated_splash_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/screens/splash_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/shared.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/app_theme.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/theme.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/theme_context.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/art_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/color_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/component_metrics_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/effects_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/gradient_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/iconography_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/motion_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/radius_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/shadow_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/spacing_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/state_layer_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/stroke_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/type_role_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/typography_tokens.dart` | Dart source | verified | FONT-001 | Local DM Sans/Public Sans role contract reviewed and theme interpolation passes | `8e97370` |
| `lib/shared/theme/typography.dart` | Dart source | verified | FONT-001 | Runtime font download removed; exact local families and numeric helper build on both platforms | `8e97370` |
| `lib/shared/widgets/amount_text.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/app_skeletonizer.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/asset_display.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_divider.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_icon_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_pill.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_app_bar.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_radio.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_toast.dart` | Dart source | fixing | UX-002 | Timer/controller disposal corrected; global helper still requires queued injectable service in Phase 3 | `8e97370` |
| `lib/shared/widgets/detail_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/grid_loader.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/squircle.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `pubspec.yaml` | Project configuration | verified | BASE-001, SDK-001, DEP-001, DEP-002, DEP-003, DEP-004, FONT-001, FLAG-001 | Immutable SDK pin, compatible constraints, Cupertino font, removed reachability dependency, and assets reviewed; external/transitional findings remain tracked | `1b3273a` |
| `scripts/git-hooks/pre-commit` | Tooling | verified | BUILD-002 | Non-mutating quality gate executes successfully | `8e97370` |
| `scripts/install-git-hooks.sh` | Tooling | unreviewed | - | - | - |
| `test/core/bootstrap/app_bootstrap_test.dart` | Test | verified | LIFE-002, LIFE-005 | Partial-construction cleanup and composed unknown-outcome failures pass | `1b3273a` |
| `test/core/bootstrap/app_loader_test.dart` | Test | verified | LIFE-002, SEC-004 | Redacted retryable and unknown-outcome bootstrap widget states pass | `1b3273a` |
| `test/core/config/app_environment_test.dart` | Test | verified | CONFIG-001, CONFIG-003 | Scheme, network, credential, protected-port, and local-development policy matrix passes | `1b3273a` |
| `test/core/di/providers_test.dart` | Test | verified | LIFE-001 | Keep-alive async repository composition remains mounted | `1b3273a` |
| `test/core/errors/failure_mapper_test.dart` | Test | verified | DEC-012, SEC-004, SEC-008 | SDK/HTTP/storage/protocol taxonomy, redaction, retry, and unknown-outcome matrix passes | `1b3273a` |
| `test/core/network/resilient_http_client_test.dart` | Test | verified | NET-001, NET-002, NET-003 | Retry/budget/abort/cancel/redirect/body/scheme/policy fault matrix passes | `1b3273a` |
| `test/features/home/bitcoin_market_repository_test.dart` | Test | verified | DATA-002 | Integer mapping, sorting, deduplication, fallback, freshness, bounds, and malformed-data cases pass | `1b3273a` |
| `test/features/home/bitcoin_market_view_model_test.dart` | Test | verified | ARCH-002 | Duplicate retry is suppressed while initial request is active | `1b3273a` |
| `test/features/wallet/rgb_wallet_engine_test.dart` | Test | verified | SDK-001, DOMAIN-002 | Stable SDK forwarding and adversarial native mapping matrix passes | `1b3273a` |
| `test/features/wallet/wallet_domain_models_test.dart` | Test | verified | DEC-013, DOMAIN-002 | Value, unit, overflow, timestamp, key, and Unicode-control invariants pass | `1b3273a` |
| `test/features/wallet/wallet_identity_generator_test.dart` | Test | verified | SEC-003, SEC-006 | CSPRNG output length, alphabet, uniqueness, and secret size pass | `1b3273a` |
| `test/features/wallet/wallet_repository_test.dart` | Test | verified | WALLET-001, LIFE-003, STORE-004, SEC-006, SEC-009 | Provision/bootstrap/reconcile/switch/resume/mnemonic transaction fault matrix passes | `1b3273a` |
| `test/features/wallet/wallet_runtime_test.dart` | Test | verified | LIFE-001, LIFE-004, SEC-006, STORE-004 | Runtime ordering, rollback, quarantine, reinit, cleanup, audit, and disposal matrix passes | `1b3273a` |
| `test/features/wallet/wallet_storage_test.dart` | Test | verified | SEC-005, STORE-001, STORE-002, STORE-003, STORE-005, STORE-006, STORE-007 | Credential, journal, corruption, ownership, legacy, collision, and timestamp matrix passes | `1b3273a` |
| `test/features/wallet/wallet_viewmodel_test.dart` | Test | verified | DEC-012, LIFE-003 | Initial loading overlap suppression passes | `1b3273a` |
| `test/goldens/presentation_components.png` | Test | unreviewed | - | - | - |
| `test/goldens/presentation_components_golden_test.dart` | Test | unreviewed | - | - | - |
| `test/shared/feedback_system_test.dart` | Test | unreviewed | - | - | - |
| `test/shared/presentation_system_test.dart` | Test | unreviewed | - | - | - |
| `test/support/wallet_fakes.dart` | Test | verified | TEST-001 | Deterministic fault-injection fakes are test-only, injectable, and cannot enter release code | `1b3273a` |
| `test/widget_test.dart` | Test | fixing | TEST-001 | Existing assertions pass on new toolchain; meaningful test expansion remains open | `8e97370` |
| `test_driver/integration_test.dart` | Project configuration | verified | TEST-002 | Standard integration-test driver compiled and executed on both platforms | `1b3273a` |
| `tool/verify_production_tracker.dart` | Tooling | verified | - | Format, sync, clean verification pass, and diff check | `163a3cf` |
<!-- FILE_INVENTORY_END -->

## Closeout Requirements

- No `unreviewed` or `fixing` file rows.
- No open finding except a documented `accepted-constraint` or a decision that
  truly requires external ownership.
- Clean second code-generation run, fatal analysis, tests, and warning-free
  `dart doc` on the exact candidate commit.
- iOS and Android build/run evidence on the exact candidate commit.
- Profile-mode frame, launch, memory, and leak evidence with device/tool details.
- Release report keeps CON-001 visible and does not claim funds-bearing mainnet
  readiness while the SDK supply-chain constraint remains accepted.
