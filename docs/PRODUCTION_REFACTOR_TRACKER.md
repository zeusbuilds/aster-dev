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
- Current phase: Phase 5, wallet features
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
| DEC-018 | verified | Preserve the established shape language: true stadium geometry for pills, rounded superellipses for cards/tiles/fields/sheets, and circles only for circular affordances. | ThemeData, shared controls, feature surfaces, shape tests, and the approved golden share this policy without changing palette or font values. |
| DEC-019 | verified | Runtime window insets are layout environment, not spacing tokens. | Typed `AsterWindowInsets` owns `padding`, `viewPadding`, and `viewInsets`; composition tests prove safe, system, and keyboard spaces remain distinct. |
| DEC-020 | verified | Route all tactile feedback through one injectable semantic haptic service. | Capability probing is shared/cached, failures cannot block actions, disabled/loading controls emit nothing, and direct plugin use is restricted to the adapter. |
| DEC-021 | verified | Present transient messages through one bounded FIFO toast queue with deduplication and an app-root host. | The bounded injectable controller supports success/failure/warning/info, accessible dismissal, safe text, deterministic advancement, and reduced motion. |
| DEC-022 | verified | Resolve animation durations through one reduced-motion policy and mute offscreen feature tickers. | Decorative loops settle when motion is disabled; navigation/toast/component transitions use effective durations; inactive tabs disable tickers and interaction. |
| DEC-023 | verified | Use the canonical Bitcoin BIPs English BIP39 list for per-word UX, while the pinned SDK remains authoritative for full mnemonic checksum validation. | The exact 2,048-word UTF-8 source is vendored with immutable provenance and SHA-256; byte, shape, order, uniqueness, membership, corruption, and concurrent-load tests pass at `5f3698f` and `05c7edf`. |
| DEC-024 | verified | Persist app preferences through one typed, versioned settings repository and generated Riverpod ViewModel. | Currency, region, Bitcoin unit, and balance visibility survive repository reconstruction; defaults preserve current behavior (`USD`, `US`, `BTC`), writes are serialized, and failure/repair paths pass at `6cc7376`. |
| DEC-025 | verified | Keep recovery phrases route-scoped and minimize copies rather than pretending Dart strings can be zeroized. | No phrase enters logs, analytics, route arguments, durable preferences, or global wallet state. Route-scoped controllers/state release references on disposal; a serialized digest-only clipboard lease clears only matching content after a bounded interval or screen exit, with fault/disposal tests passing at `05c7edf`. Screenshot policy remains the separate SEC-011 decision. |
| DEC-026 | verified | Route access is derived from the durable active-wallet state. | Empty registries enter onboarding; wallet-only routes redirect to onboarding; confirmed provisioning reloads registry state before replacing navigation with Home. Pure-policy and real GoRouter tests pass at `518b077`; configured native restart evidence remains ROUTE-002 rather than weakening this invariant. |
| DEC-027 | blocked | Do not expose seed or xpub disclosure actions before SEC-007 is decided. | Advanced settings may expose truthful network diagnostics now, but sensitive rows remain disabled and explicitly unavailable rather than bypassing authentication policy. |
| DEC-028 | verified | Accept bounded multiword paste at the import fields without programmatically reading the system clipboard. | Input is lowercased, stripped to canonical word characters, capped to 12 BIP39-sized words, distributed from the focused field, and still requires SDK checksum validation; focused UX and adversarial tests pass at `05c7edf`. |
| DEC-029 | blocked | Never remove detected legacy seed records merely to unblock startup. | Product must choose between an explicit-consent, idempotent in-app migration and a support-assisted recovery release. Either path must preserve the old record until a new ownership-bound wallet commit is proven. |
| DEC-030 | verified | Stable feature navigation carries a product asset/rail target; repositories resolve it to deployment-owned contract metadata before wallet execution. | Prevents route arguments, ticker text, or presentation models from substituting an RGB contract ID or precision. Focused domain/configuration/repository tests pass in the Phase 5 foundation slice. |
| DEC-031 | verified | Own Bitcoin payment-URI policy in the app, using exact-pinned pure-Dart codecs only for Base58Check and Bech32/Bech32m primitives. | User-entered and native-returned on-chain addresses pass checksum, witness-program, and configured-network validation at `021a610`. BIP321 on-chain fallback amounts use integer satoshis, unknown optional instructions are accepted only with a valid fallback, and unsupported `req-*` instructions fail closed. Route-aware embedded Lightning instruction handling remains PAY-003. |
| DEC-032 | fixing | A product route selects Bitcoin on-chain or Lightning before a BIP321 URI is decoded; URI contents never switch rails. | The selected on-chain route accepts a valid fallback or the first compatible repeated `bc`/`tb`/`bcrt` instruction in sender order. The selected Lightning route extracts exactly one BOLT11 instruction and rejects multiple invoices because the app has no invoice-choice UI. Unsupported `req-*` instructions fail closed; optional `pop` is never opened or retained. Focused parser/repository/runtime/DI tests pass; aggregate verification is pending. |

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

## Phase 3 Evidence

| Check | Result | Exact evidence |
| --- | --- | --- |
| Implementation commits | Recorded | `98b7a40` (`Normalize presentation systems and interaction feedback`) and `3f1215b` (`Enforce accessible presentation contrast and goldens`). |
| Palette and fonts | Pass | Existing color values are unchanged. Bundled DM Sans remains the UI family and Public Sans is applied only to numeric spans; symbols, units, labels, addresses, and asset names remain DM Sans. |
| Generation | Pass | `fvm dart run build_runner build` processed 212 inputs; an immediate second run skipped all 212 and wrote zero outputs. |
| Format and analysis | Pass | The Phase 3 candidate passes repository-wide Dart formatting and `fvm flutter analyze --fatal-warnings --fatal-infos` with zero diagnostics. |
| Host tests | Pass | `fvm flutter test --coverage`; 153 tests pass, including shape, numeric typography, haptic failure isolation, bounded toast ordering/deduplication, reduced motion, hidden-tab ticker suppression, keyboard activation, navigation geometry, golden, touch-target, label, and contrast checks. |
| Coverage | Partial, tracked | 2,897 of 7,341 instrumented Dart lines, 39.46%. Presentation infrastructure is covered materially; feature end-to-end, onboarding, payment flows, and measured performance remain TEST-001. |
| Golden and accessibility | Pass | `test/goldens/presentation_components.png` was rendered with bundled app and icon fonts and visually inspected. Flutter's Android tap-target, labeled-target, and text-contrast guidelines pass. A discovered 3.24:1 tertiary-copy misuse was corrected without changing palette values. |
| Dart documentation | Pass | Fresh isolated `dart doc` output contains 190 public libraries with zero warnings and zero errors. |
| iOS simulator build | Pass with tracked SDK warning | Clean `fvm flutter build ios --simulator --debug`; Runner executable is 123,808 bytes, SHA-256 `177baf78ac956c10a20b9c3ff89e591787613165e7a39fadccfda57f0d729704`. The immutable SDK's CocoaPods-only integration remains SDK-002. |
| iOS install and launch | Pass with newly tracked product blocker | XcodeBuildMCP built, installed, and launched on iPhone Air / iOS 26.5 as process 2997. Existing simulator data correctly failed closed at legacy-wallet detection, but the screen provides no recovery action; STORE-008 records that Phase 4 blocker. |
| Android release build | Pass with tracked constraints | Clean arm64 release APK is 247,705,546 bytes, SHA-256 `a9e4054078ed8b769916345834ac4110432ea27f2df1a251069de312146d85c7`. Debug signing remains PLAT-001 and built-in Kotlin migration remains PLAT-002. |
| Policy searches | Pass for Phase 3 scope | Direct haptic plugin use exists only in its adapter; feature/shared UI has no raw `Color`/`Colors`, typography-size/weight overrides, `SnackBar`, `ScaffoldMessenger`, `OverlayEntry`, rounded-rectangle shape, or `ClipRRect` leakage. Remaining scan plugin ownership is independently tracked as ARCH-004. |
| Tracker inventory | Pass | 312 non-generated repository files after Phase 3, including presentation-system docs and golden evidence; inventory sync and verifier pass. |
| Delivery | Blocked | Pushes of `98b7a40` and `3f1215b` to the configured Zeus origin failed with GitHub `Repository not found`; no remote or global Git identity was changed. |

## Phase 4 Incremental Evidence

| Check | Result | Exact evidence |
| --- | --- | --- |
| Settings implementation | Pass | Commit `6cc7376` adds typed/versioned preferences, serialized writes, bounded catalog loading, generated Riverpod ViewModels, Bitcoin-unit selection, advanced settings, and redacted network diagnostics. |
| Mnemonic foundation | Pass | Commit `5f3698f` vendors and integrity-checks the canonical BIP39 English list, keeps SDK checksum authority, adds transactional wallet creation results, and introduces a digest-only bounded clipboard lease. |
| Onboarding implementation | Pass | Commit `05c7edf` adds route-scoped generated ViewModels, 12 real fields, bounded phrase paste, SDK checksum validation, current-screen loading, duplicate suppression, exact registry adoption, and guarded root navigation. |
| Monetary formatting | Pass | Integer-only BTC/sats formatting covers zero, negative, boundary, grouping, and fractional-display cases without `double` conversion. App-wide feature consumption remains `SETTINGS-001`. |
| Catalog integrity | Pass | Production JSON catalogs load under tests; duplicate ISO identities are canonicalized deterministically by first curated occurrence, invalid persisted values self-heal to typed defaults, and raw loader failures do not reach UI state. |
| Flags and dependency graph | Pass | Currency and region UI use `circle_flags`; `country_flags`, `jovial_misc`, and `jovial_svg` no longer resolve in `pubspec.lock`. |
| Generation | Pass | `build_runner` processed 257 inputs; an immediate second run skipped all 257 and wrote zero outputs. |
| Format and analysis | Pass | Repository-wide format checked 270 Dart files with zero changes; fatal-warning/fatal-info analysis has zero diagnostics. |
| Host tests | Pass on `05c7edf` | 193 tests pass with 54.97% aggregate line coverage. Onboarding coverage includes operation overlap, stale checksum completion, native failure, timer disposal, compact/large layouts, 2x text scaling, touch targets, labels, and contrast. |
| Dart documentation | Pass | Fresh isolated output documents 225 public libraries with zero warnings and zero errors. |
| Tracker inventory | Pass after sync | 359 non-generated repository files are represented; the Phase 4 onboarding files are reconciled to implementation commit `05c7edf`. |
| Delivery | Blocked | Pushes through evidence commit `bb393e3` to the configured Zeus origin fail with GitHub `Repository not found`; no remote, global identity, or credential configuration was changed. |
| Post-implementation audit | Pass at `518b077` | Real GoRouter, 390-point loaded-home, native accessibility, cold-link Back, ViewModel-boundary, and onboarding-art audits found and closed `ROUTE-003`, `HOME-002`, `ONB-004`, `DS-005`, `ACCESS-004`, and `ACCESS-005`. |
| Post-audit generation | Pass at `518b077` | `build_runner` processed 258 inputs; an immediate second run skipped all 258 inputs and wrote zero outputs. |
| Post-audit host gates | Pass at `518b077` | Repository format is clean, fatal-warning/fatal-info analysis has zero diagnostics, and 197 tests pass with 5,696 of 8,626 instrumented lines covered (66.03%). |
| Post-audit Dart documentation | Pass at `518b077` | Fresh isolated output documents 225 public libraries with zero warnings and zero errors. |
| Post-audit iOS build | Pass with tracked SDK warning | Debug iOS Simulator Runner is 123,808 bytes, SHA-256 `e04c84b77804cba1be5715aaf6062b2bb7997b84c2cc8548222628b59392168b`; SDK SwiftPM remains SDK-002. |
| Post-audit Android build | Pass with tracked constraints | Arm64 release APK is 247,502,573 bytes, SHA-256 `3b34836fb88ec6aeddfc8177232669f524db8d598c6c0c4c7101ce57e74e3557`; backup and cleartext are disabled. Debug signing remains PLAT-001 and Kotlin migration remains PLAT-002. |
| Post-audit iOS runtime | Pass for audited paths | An unchanged app build on a disposable iPhone Air/iOS 26.5 exposed Create/Import as actions and exactly four directly typeable recovery fields. `ABANDON1` normalized to `abandon`; app runtime logs had zero crash and secret-keyword matches. The app/simulator were stopped and deleted; original simulator data was untouched. |
| Post-audit Android runtime | Pass for audited paths | The exact APK on a disposable API 36 arm64 AVD exposed enabled Create/Import buttons as clickable and exactly four single clickable/editable recovery nodes. `ABANDON1` normalized to `abandon` with `valid word`; app-process logs had zero crash and secret-keyword matches. The app/AVD were stopped and deleted. |
| Successful native provisioning/restart | Blocked, not claimed | Fresh create reached the real SDK and failed with a redacted node-operation message because no configured RLN/LSP service is available. No success or navigation was simulated. A successful process-restart smoke remains ROUTE-002/TEST-001 work. |
| Post-audit tracker inventory | Pass | All 360 non-generated repository files are represented and implementation rows are reconciled to `518b077`. |

## Phase 5 Incremental Evidence

| Check | Result | Exact evidence |
| --- | --- | --- |
| Payment-domain foundation | Pass at `044a75c` | Four stable `bitcoin/usdt` by `onchain/lightning` targets remain independent from chain environment. The repository resolves targets to immutable deployment metadata and returns a typed configuration failure for absent USDT instead of guessing identity. |
| RGB deployment configuration | Partial by design | `UTEXO_USDT_ASSET_ID` and `UTEXO_USDT_PRECISION` are validated as an all-or-nothing pair. Fail-closed behavior passes; real environment values remain the external `CONFIG-002` blocker. |
| Host gates | Pass at `044a75c` | Repository format is clean, all 203 tests pass, fatal-warning/fatal-info analysis has zero diagnostics, tracker inventory matches all 360 non-generated files, and `git diff --check` passes. |
| Typed payment execution | Pass at `605b50c` | App-owned receive, preview, send, and portfolio contracts preserve exact units and redact encoded values from diagnostics. Repository operations resolve deployment-owned routes, stay behind the serialized runtime, suppress invalid native calls, and map typed failures. The SDK adapter revalidates invoice network, asset, amount, and expiry and rejects malformed native identifiers. |
| Payment boundary host gates | Pass at `605b50c` | Deterministic generation and formatting are clean, fatal-warning/fatal-info analysis has zero diagnostics, all 220 tests pass, tracker inventory matches all 362 non-generated files, `git diff --check` passes, and `dart doc --validate-links` documents 227 libraries with zero warnings/errors. |
| Bitcoin destination implementation | Pass at `021a610` | Exact integer BIP321 on-chain fallback parsing, Base58Check, BIP173, and BIP350 validation guard repository previews/sends and native receive/send boundaries. Parser results are privately constructed; official and adversarial vectors plus mutation-suppression tests pass. |
| Bitcoin destination host gates | Pass at `021a610` | Deterministic generation and formatting are clean, fatal-warning/fatal-info analysis has zero diagnostics, all 231 tests pass at 67.34% line coverage, tracker inventory matches all 365 non-generated files, `git diff --check` passes, and fresh `dart doc --validate-links` documents 229 libraries with zero warnings/errors. |

## Phase Plan

| Phase | Scope | Status | Exit evidence |
| --- | --- | --- | --- |
| 0 | Inventory, baseline, tracker, decisions, and audit tooling | verified | Inventory validator, baseline evidence, all files classified. |
| 1 | Flutter/Dart pin, dependency resolution, analysis, generation, fonts, CI, and platform baseline | verified | Clean format/analyze/test/doc plus iOS and Android compile. |
| 2 | Domain architecture, SDK lifecycle, repositories, models, error/result policy, networking, storage, and security | verified | Unit/contract/fault tests, real platform storage tests, and both platform builds pass at `1b3273a`. |
| 3 | Design system and shared UX systems | verified | Semantic shape/inset/haptic/toast/motion systems, strict analysis, 153 host tests, approved golden/accessibility gates, and both platform builds pass at `3f1215b`. |
| 4 | Onboarding and settings | fixing | Create/import/restart/unit/advanced end-to-end evidence. |
| 5 | Home, send, receive, swap, activity, and transaction details | fixing | Truthful four-rail flows and integration/widget evidence. |
| 6 | Documentation, performance, memory, platform hardening, and release evidence | unreviewed | Exact-candidate release report with measurements and constraints. |
| 7 | Independent file-by-file closeout | unreviewed | Zero unreviewed files and zero untracked non-accepted findings. |

## Findings

| ID | Severity | Area | Status | Finding | Evidence | Fix commit | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BASE-001 | P0 | Toolchain | verified | Flutter 3.38.9 / Dart 3.10.8 could not consume the SDK, which requires Flutter 3.41+ / Dart 3.11+. | `.fvmrc`, `pubspec.yaml`, SDK `pubspec.yaml` | `8e97370` | Flutter 3.44.9 / Dart 3.12.2 gates and both platform builds pass. |
| SDK-001 | P0 | Integration | verified | The immutable public `rgb_sdk_flutter` dependency needs one app-owned `UtexoWallet` owner and a DTO-isolating repository adapter. | `pubspec.yaml`; SDK import and ownership audit | `1b3273a` | SDK imports are restricted to `RgbWalletEngine` and typed failure mapping; runtime/repository tests and both platform builds pass. |
| DATA-001 | P0 | Product truth | unreviewed | Production UI presents static/mock balances, prices, activity, wallet identifiers, addresses, and delayed loading behavior. | Baseline runtime and source search | - | - |
| SEND-001 | P0 | Send | unreviewed | Send opens directly on a form prefilled with a sample Bitcoin address and has no asset/rail selection or real submission. | Baseline Send screenshot | - | - |
| ONB-001 | P0 | Onboarding | verified | Create was a dead action; import rendered hardcoded sample words, had no editable fields/checksum validation, and never provisioned through the wallet lifecycle. | Baseline Welcome/Import screenshots, accessibility snapshot, and Phase 4 source audit | `05c7edf` | Route-scoped create/import ViewModels use real SDK generation/checksum/provisioning, current-screen operation state, duplicate suppression, typed failure, and guarded root replacement; focused and aggregate tests pass. |
| ONB-002 | P1 | Onboarding input UX | verified | Import lacked lowercase normalization, autofill/autocorrect controls, field focus order, keyboard Next/Done behavior, carousel handoff at words 4/8, and secret-safe semantics. | Import screen/widget audit | `05c7edf` | Twelve editable fields normalize safely, expose per-word status, coordinate focus/carousel/submit, accept bounded multiword paste, dispose secret state, and pass compact/large/text-scale/accessibility tests. |
| ONB-003 | P0 | Mnemonic validation | verified | Per-word onboarding feedback had no canonical vocabulary source, integrity gate, or separation from authoritative checksum validation. | Phase 4 asset/repository audit | `5f3698f`, `05c7edf` | Pinned canonical vocabulary integrity tests pass and full checksum authority remains serialized behind the SDK-backed wallet repository. |
| ONB-004 | P1 | Onboarding input boundary | verified | Character filtering and maximum BIP39 word length were enforced only by the TextField formatter, so direct ViewModel callers could bypass the input invariant. | Post-`05c7edf` ViewModel boundary audit | `518b077` | The ViewModel independently lowercases, strips non-letters, and caps every incoming word before vocabulary/checksum evaluation; direct character and length-boundary tests pass. |
| LIFE-001 | P0 | Lifecycle | verified | No single serialized owner existed for native wallet init, unlock, sync, reinit, shutdown, and destroy. | Source inventory and fault-path review | `1b3273a` | One injectable `WalletRuntime` serializes every native lifecycle and operation path; concurrency, reinit, rollback, disposal, and retry tests pass. |
| SEC-001 | P0 | Logging | verified | The unused HTTP logging interceptor could emit request/response bodies and sensitive native/network material. | `lib/core/network/interceptors/logging_interceptor.dart` | `8e97370` | Dead Chopper/interceptor surface and dependencies removed; repository search and fatal analysis pass. A production logging policy is still required in Phase 2. |
| PLAT-001 | P0 | Platform identity | blocked | Android/iOS use `com.example` identifiers and Android release uses debug signing. | Platform build files; DEC-006 | - | - |
| TEST-001 | P0 | Testing | fixing | Baseline had only two token assertions and no behavioral, platform, integration, accessibility, golden, lifecycle, or performance coverage. | Baseline through Phase 4 post-audit slice | `1b3273a`, `3f1215b`, `6cc7376`, `05c7edf` | 197 host tests pass at 66.03% line coverage plus real storage tests on each platform, real GoRouter tests, and simulator/emulator presentation/accessibility smokes. Successful configured-wallet restart, Phase 5 feature end-to-end, physical assistive-tech/haptics, and measured performance evidence remain open. |
| BUILD-001 | P1 | Android | verified | Baseline Android build could not download Gradle and therefore did not compile. | Baseline `flutter build apk --debug` timeout | `8e97370` | Exact current-candidate x86_64 debug APK packages successfully; artifact hash is recorded above. |
| DOC-001 | P1 | Documentation | unreviewed | Architecture and setup material describe Aster/GDK/Boltz/Liquid-era concepts instead of the target UTEXO SDK architecture. | `README.md`, `docs/architecture/` | - | - |
| DOC-002 | P2 | API docs | verified | `dart doc` emitted two unresolved `[enableLogging]` references. | Baseline dartdoc output | `8e97370` | `dart doc --validate-links` completes with zero warnings and zero errors. |
| DOC-003 | P1 | Development setup | verified | Development instructions described removed import tools, non-fatal analysis, Flutter 3.38, and referenced no SDK override contract. | `docs/DEVELOPMENT.md`; `pubspec.yaml` comment | `8e97370` | Guide now matches executable Make/CI gates and documents a non-committed local SDK override. |
| DEP-001 | P1 | Dependencies | verified | Direct constraints were stale, `intl` was unconstrained, and unused architecture packages remained direct dependencies. | Baseline `flutter pub outdated`; consumer searches | `8e97370` | Direct dependencies were deliberately upgraded or removed; compatibility pins are recorded in DEC-007 and DEC-008. |
| DEP-002 | P2 | SDK dependency graph | blocked | Discontinued transitive package `js` 0.7.2 remains through `pointycastle` 3.9.1, which is constrained by the immutable SDK dependency. | `flutter pub deps`; SDK `pubspec.yaml` | - | Requires a future SDK revision that supports pointycastle 4 or removes that dependency; do not override the pinned SDK graph in the app. |
| FLAG-001 | P2 | Assets/dependencies | verified | `circle_flags` and `country_flags` coexisted despite one required flag implementation. | `pubspec.yaml`, settings/send/receive imports, resolved dependency graph | `6cc7376` | All app flag consumers use `circle_flags`; `country_flags` and its two otherwise-unused transitive packages are absent from `pubspec.lock`, and all host gates pass. |
| FONT-001 | P1 | Determinism | verified | UI typography relied on `google_fonts` rather than bundled exact DM Sans and Public Sans assets. | Theme source and `pubspec.yaml` | `8e97370` | Exact variable fonts and OFL licenses are bundled with recorded provenance/checksums; iOS and Android builds pass offline font registration. |
| NET-001 | P1 | Reliability | verified | The network layer lacked a uniform timeout, idempotent retry/backoff, failure taxonomy, and safe observability policy. | `lib/core/network/`; transport fault tests | `1b3273a` | Abortable GET-only retries run under one monotonic budget with bounded backoff/jitter, `Retry-After`, body limits, and redacted typed failures; all fault tests pass. |
| UX-001 | P1 | Shared UX | verified | Haptics were called directly from widgets with repeated capability probes and no semantic/testable policy owner. | Direct plugin call-site audit; DEC-020 | `98b7a40` | One injectable semantic service owns cached capability and failure isolation; all app consumers use intents and adapter fault tests pass. |
| UX-002 | P1 | Shared UX | verified | Toasts lacked queued/deduplicated ownership, scan used `SnackBar`, and settings exposed fake result demonstrations. | Toast/SnackBar/overlay search; DEC-021 | `98b7a40` | One bounded FIFO controller and app-root host own accessible result presentation; direct alternatives and fake settings demonstrations are removed; queue tests pass. |
| ACCESS-001 | P1 | Accessibility | fixing | Baseline semantics included empty/duplicated labels and omitted editable mnemonic fields. | Xcode runtime accessibility snapshots and Phase 4 control audit | `05c7edf` | Onboarding/settings host gates prove labeled state, focus order, minimum targets, contrast, and 2x text-scale layouts. Native-tree defects discovered afterward are tracked separately as ACCESS-004/005; physical VoiceOver/TalkBack traversal remains open. |
| ACCESS-004 | P1 | Button native semantics | verified | `CustomButton` excluded descendant semantics without owning a semantic tap action, so Android exposed enabled primary buttons as non-clickable even though pointer taps worked. | Disposable Android API 36 UIAutomator audit after `05c7edf` | `518b077` | The shared semantic boundary owns `onTap` only while enabled; host tests assert tap-action presence/absence and the exact APK exposes both onboarding primary actions as clickable. |
| ACCESS-005 | P1 | Editable native semantics | verified | Recovery fields initially exported a labeled wrapper plus an unlabeled native text field; simply excluding the child removed the duplicate but also removed real edit actions. | iOS/Android native accessibility trees plus host semantic-action audit after `05c7edf` | `518b077` | Each field uses one merged semantics boundary preserving the authoritative `TextField` value and tap/focus/setText/selection actions while adding its numbered label and validation hint. Host actions plus fresh iOS/Android native trees pass. |
| ROUTE-001 | P1 | Routing | unreviewed | Current routes do not model asset/rail flow state or transaction details by stable ID. | Routing source inventory | - | - |
| ROUTE-002 | P0 | Wallet access | fixing | Router previously entered the wallet shell without a durable active-wallet guard, so a fresh install could reach wallet UI and onboarding success could not establish a guarded root transition. | `app_router.dart`, `route_guards.dart`, bootstrap/registry flow | `05c7edf` | Durable-state policy plus real GoRouter cold-link, persisted-active, and live-provision transition tests pass. A successful native provision followed by process restart remains blocked on configured wallet services and is not claimed. |
| ROUTE-003 | P1 | Onboarding navigation | verified | Create/import Back actions called `pop` even when a cold onboarding deep link had no prior route, leaving no safe in-app destination. | Real GoRouter cold-link integration test after `05c7edf` | `518b077` | Back pops an existing stack or replaces a root deep link with onboarding welcome; the real router test passes. |
| HOME-001 | P1 | Home | unreviewed | The visibility control is not wired or persisted; asset rows do not represent BTC/RGB aggregate balances from real data. | Baseline Home and source | - | - |
| HOME-002 | P1 | Home responsive layout | verified | A real loaded Bitcoin price overflowed the market header by 184 pixels at a 390-point phone width. | Real-router loaded-data widget test after `05c7edf` | `518b077` | The title and numeric value share bounded flex space and scale the numeric display down only when required; the 390x844 router regression passes. |
| RECV-001 | P1 | Receive | unreviewed | Receive has no asset/rail selection or real invoice lifecycle and includes obsolete Direct Peg In behavior. | Baseline Receive and source | - | - |
| SWAP-001 | P1 | Swap | unreviewed | Swap assets do not match the target domain and execution must be made explicitly unavailable without simulating success. | Swap source; CON-002 | - | - |
| TX-001 | P1 | Activity | unreviewed | There is no normalized cross-rail activity model or transaction-details route/screen. | Transaction source inventory | - | - |
| SETTINGS-001 | P1 | Settings | fixing | Bitcoin unit and required advanced wallet/network settings were absent or placeholders; currency/region selection was not persisted. | Settings implementation and tests at `6cc7376` | `6cc7376` | Typed preferences, selection screens, advanced navigation, redacted network diagnostics, and SEC-007 gating are implemented. Applying the selected unit to every feature amount remains Phase 5 work. |
| SETTINGS-002 | P1 | Settings architecture | verified | Stateful screens performed asset I/O, owned selection/loading/error state, and popped before any durable write; model classes owned unbounded static caches and leaked exception text. | Repository/ViewModel/screen tests and source-boundary audit | `6cc7376` | Catalog I/O and serialized durable writes sit behind typed repository/ViewModel boundaries; controls wait for success, suppress overlap, expose retry, and retain redacted failures. |
| SETTINGS-003 | P1 | Catalog identity | verified | The production currency catalog contains duplicate ISO identities, so persisted ISO code could map ambiguously or make single-value lookup throw. | Production-catalog invariant test and repository review | `6cc7376` | Catalog loading canonicalizes by ISO code in curated source order before validating persisted identity; production data and restart/repair tests pass. |
| BRAND-001 | P1 | Product identity | fixing | Flutter product constants say UTEXO while visible copy, iOS/Android display metadata, privacy strings, and the settings version footer still carry Aster-era or hardcoded identity. | Repository-wide product-string and platform metadata audit | - | Onboarding and settings visible brand copy now say UTEXO. Platform labels/privacy copy and runtime package-version ownership remain Phase 6 work; final identifiers/signing remain DEC-006. |
| SAFE-001 | P2 | Layout | verified | Safe-area helpers lived in spacing and mixed `padding`, `viewPadding`, and keyboard obstruction behind ambiguous names. | Insets and SafeArea call-site audit; DEC-019 | `98b7a40` | Typed window insets own safe/system/keyboard spaces, spacing is purely spatial, consumers avoid double padding, and composition tests pass. |
| PERF-001 | P1 | Performance | unreviewed | No measured launch, frame, memory, leak, rebuild, cache, or SDK-handle baseline exists. | Test/tooling inventory | - | - |
| SEC-002 | P0 | Seed security | verified | Two hardcoded 12-word mnemonics were compiled into the app, printed around migration activity, and written to secure storage at startup. | `lib/core/utils/wallet_migration_service.dart`; `lib/main.dart` | `8e97370` | Migration and startup writes removed; repository search contains no mnemonic fixture or logging path. |
| SEC-003 | P0 | Seed privacy | verified | Legacy wallet identity and display name were deterministically derived directly from mnemonic text, creating a stable seed fingerprint outside the SDK lifecycle. | `wallet_id_generator.dart`; legacy `wallet_model.dart` | `8e97370` | Seed-derived generator removed; replacement `WalletProfile` accepts only an opaque post-SDK wallet ID and non-secret metadata. |
| GIT-001 | P1 | Delivery | blocked | Repository-local Zeus commits succeed, but the active host credential is not authorized for origin and GitHub returns `Repository not found`. | Push of Phase 5 Bitcoin destination commit `021a610` | - | Restore project-scoped Zeus access; do not change global identity or remote. |
| BUILD-002 | P1 | Code generation | verified | The original Riverpod 2.4 generator used analyzer 6.4, which only understood Dart 3.4 while the app now uses Dart 3.12. | Baseline Phase 1 build-runner warning | `8e97370` | Riverpod 3.3.2 / generator 4.0.4 resolves analyzer 12.1; generation completes without a language-version warning. |
| ARCH-001 | P1 | Networking/DI | verified | Unused Chopper clients, duplicate interceptors, and no-op DI modules exposed stale APIs and an unsafe body logger. | Consumer search found definitions only | `8e97370` | Removed the dead Chopper surface and dependency; fatal analyzer is clean. |
| PLAT-002 | P2 | Android toolchain | blocked | Flutter 3.44 warns that the app and `haptic_feedback`, `mobile_scanner`, and `rgb_sdk_flutter` apply the legacy Kotlin Gradle plugin, which a future Flutter release will reject. | Exact Android build output | - | App migration requires Flutter 3.47+; plugin owners must also publish built-in Kotlin support. Current AGP 9.0.1/Kotlin 2.3.20 build passes with Flutter-generated compatibility flags. |
| SDK-002 | P2 | iOS packaging | blocked | The pinned `rgb_sdk_flutter` revision does not support Swift Package Manager, which Flutter warns will become mandatory in a future release. | Exact iOS simulator build output | - | CocoaPods integration passes now; resolve in a future immutable SDK revision before Flutter removes fallback support. |
| TOOL-001 | P2 | Build environment | verified | Host disk exhaustion interrupted the first exact Android APK packaging attempt after compilation. | `:app:packageDebug` `No space left on device` | - | Removed only disposable caches and local build output; identical candidate build passed without touching protected regtest, simulator/emulator, source, or user data. |
| TOOL-002 | P3 | iOS simulator | blocked | iOS 26.5 logs duplicate `UIAccessibilityLoaderWebShared` implementations from its WebCore and WebKit accessibility bundles during launch. | Exact Phase 1 runtime log for process 45978 | - | This originates inside the Apple simulator runtime, not the app bundle. Recheck on a future simulator runtime and physical device; no app exception accompanied it. |
| SEC-004 | P0 | Error privacy | verified | Route errors and generic HTTP/exception handling could expose raw exception strings or response bodies to users and diagnostics. | `app_router.dart`; removed `error_handler.dart`; failure tests; scanner presentation audit | `1b3273a`, `98b7a40` | Route, transport, SDK, storage, bootstrap, and scanner presentation expose stable redacted messages/codes only; strict searches and failure tests pass. |
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
| PAY-001 | P0 | Bitcoin destination validation | verified | The pinned SDK exposes no non-mutating Bitcoin address/payment-URI decoder, and bounded-string validation could not prove checksum, witness program, required parameters, or network before a send mutation. | SDK public-API audit; app-owned parser/repository/runtime review; focused and aggregate gates | `021a610` | Exact integer BIP321 on-chain fallback parsing validates Base58Check, BIP173, and BIP350 vectors, configured network, required/duplicate instructions, unsafe metadata, native receive output, and pre-mutation sends. All 231 host tests pass. |
| PAY-002 | P0 | Payment execution boundary | verified | Feature flows had no app-owned exact-unit receive, preview, send, or cross-rail portfolio contracts and could not safely map the four product targets to native operations. | Wallet domain, repository, runtime-adapter, and behavior-vector tests | `605b50c` | Typed contracts, deployment-owned route resolution, serialized calls, mutation suppression, invoice revalidation, and malformed native-output rejection pass focused tests. No SDK DTO crosses the repository boundary. |
| PAY-003 | P1 | Unified payment instructions | fixing | A BIP321 URI can carry a Lightning instruction with or without an on-chain fallback, but passing the whole URI to the native decoder would fail and silently selecting a different rail would violate user intent. | Official BIP321 review; route-aware parser, repository, runtime, and DI tests | - | One app-owned parser now preserves the selected rail, validates exact on-chain requests, extracts a single BOLT11 value before native decode/send, rejects unsupported required or ambiguous Lightning instructions, preserves RFC 3986 `+` semantics, and never retains the source URI. The focused 67-test matrix passes; full aggregate gates and exact-commit evidence remain. |
| DEP-005 | P1 | Bitcoin codec supply chain | verified | Checksum-valid Bitcoin parsing required codec primitives not provided by Flutter or the pinned SDK's stable public API. | Package source/license audit; `pubspec.lock`; official BIP vectors | `021a610` | `bs58check` 1.0.2 and `dart_bech32` 2.0.0 are exact direct MIT dependencies with hosted lockfile hashes; the app owns URI, amount, and network policy, and official/adversarial vectors plus aggregate gates pass. |
| NET-002 | P1 | Cancellation | verified | Whole-operation HTTP timeout did not abort an active request and could permit retries after the caller had timed out. | Abortable transport tests | `1b3273a` | `AbortableRequest` and one monotonic operation budget abort active I/O and prevent later attempts; timeout/cancellation tests pass. |
| DEP-003 | P2 | Dependency hygiene | verified | `connectivity_plus` and its provider abstraction were unused and could encourage treating reachability hints as request truth. | Consumer search and dependency graph | `1b3273a` | Package/provider removed; request-result-based reachability policy is documented and both platform builds pass. |
| PLAT-003 | P0 | Android backup | verified | Wallet databases, preferences, or encrypted storage could enter Android cloud backup or device transfer. | Android manifest and extraction rules | `1b3273a` | Release manifest has `allowBackup=false` and restrictive legacy/Android 12+ rules; platform tests and release build pass. |
| CONFIG-002 | P0 | RGB asset identity | blocked | No deployment-owned RGB USDT contract ID and precision are configured, so the app cannot truthfully identify or aggregate USDT on any target environment. | Product requirements and Phase 5 fail-closed configuration tests | - | The app now validates the two values as one deployment contract and keeps USDT routes unavailable when absent. Real per-environment values are still required; identity is never inferred from ticker text. |
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
| SEC-010 | P0 | Mnemonic UI lifetime | verified | Import/create UI had no defined secret lifetime, clipboard clearing, route/state ownership, or tests proving phrases do not enter logs, preferences, or navigation arguments. | Phase 4 secret-flow audit; DEC-025 | `05c7edf` | Route-scoped state, bounded digest-only matching clipboard clearing, disposal cleanup, secret-safe diagnostics/routes, and source/fault tests pass. Platform capture policy remains the separate blocked SEC-011 decision. |
| SEC-011 | P0 | Screen capture policy | blocked | Background app-switcher snapshots are obscured, but the product has not decided whether recovery-phrase screens must block Android screenshots and screen recording or detect/obscure capture on iOS where equivalent prevention is not universally available. | Phase 4 mnemonic threat-model review | - | Requires a product/security policy covering screenshots, screen recording, support implications, and accepted platform asymmetry before release qualification of phrase display. |
| DEP-004 | P1 | Release assets | verified | The first Android release build exposed an unbundled Cupertino icon font reachable through Flutter framework code. | Initial release build warning; `pubspec.yaml`; rebuilt APK | `1b3273a` | `cupertino_icons` 1.0.9 is explicitly bundled and the exact release build reports successful tree shaking instead of a missing font. |
| PLAT-005 | P1 | Android compilation | verified | The first native policy implementation called unavailable `android.system.Os.rmdir`, breaking Kotlin compilation. | Android integration build failure and corrected bridge | `1b3273a` | Cleanup verifies an empty owned directory and uses checked `File.delete()` with bounded error mapping; Android integration and release builds pass. |
| TOOL-003 | P2 | Physical iOS evidence | blocked | The app built and installed on a connected iPhone, but Flutter could not attach to the VM service over the wireless/local-network path. | Device `00008130-000A552C3EBA001C` run log | - | This does not invalidate simulator/native test evidence, but physical iOS runtime, haptic, performance, and memory evidence remains required in Phase 6. |
| DOC-004 | P1 | Documentation gate | fixing | Reusing the ignored default `doc/api` output retained obsolete pages and produced 217 false stale-file warnings. | First Phase 2 dartdoc run versus fresh-output rerun | - | A fresh isolated output produced 178 libraries with zero warnings/errors. Phase 6 must make that clean-output behavior part of the repeatable release command and CI/documentation contract. |
| DS-001 | P1 | Shape system | verified | Material theme components and several shared/feature surfaces used rounded rectangles where the product contract requires squircles, while pills were not modeled separately. | Theme, surface, bottom-sheet, navigation, and control audit | `98b7a40` | Theme and controls use rounded superellipses or true stadiums by semantic role; type assertions and golden review pass with unchanged palette values. |
| DS-002 | P1 | Numeric typography | verified | `NumericText` applied Public Sans to entire mixed strings and included symbols/units in numeric chunks. | `amount_text.dart`; all numeric call sites | `98b7a40` | Numeric-span parsing tests and golden inspection prove only digits, signs, and numeric separators use Public Sans; surrounding copy inherits DM Sans. |
| DS-003 | P1 | Theme integrity | verified | `ThemeContext` silently constructed fallback extensions when the app theme was incomplete. | `theme_context.dart`; bootstrap theme ownership | `98b7a40` | Every app/bootstrap surface is themed and missing required extensions fail fast under explicit widget tests. |
| DS-004 | P2 | Component recipes | verified | Loader, chart, and splash visual recipes exposed reusable geometry and effects outside owning semantic systems. | Component metrics, effects, art, loader, chart, and splash audit | `98b7a40` | Reusable geometry/effects live in semantic extensions; local painters retain only derived interpolation. Golden, reduced-motion, and update tests pass. |
| DS-005 | P2 | Onboarding art roles | verified | The onboarding icon grid encoded repeated strong/faint alpha values, highlight coordinates, and indicator expansion directly in feature UI. | Post-`05c7edf` onboarding file audit | `518b077` | Semantic alpha roles live in `AsterEffects`; authored highlight and indicator metrics live in `AsterArt`; the feature retains only its one-off row-major tile composition. Theme-extension and presentation gates pass. |
| MOTION-001 | P1 | Reduced motion | verified | Looping loaders, shimmer, chart choreography, splash, button scale, navigation, toast, and swap choreography ignored the platform's disable-animation preference. | Animation-controller and implicit-animation audit | `98b7a40` | One motion policy resolves effective duration; decorative loops stop in a stable state and transitions complete safely when motion is disabled. |
| MOTION-002 | P1 | Offscreen work | verified | `IndexedStack` kept feature screens mounted without explicitly muting hidden tickers or interaction. | `skeleton_screen.dart`; ticker and semantics tests | `98b7a40` | Inactive tabs use `TickerMode`, `IgnorePointer`, and excluded semantics; hidden screens remain mounted without animation or input work. |
| ACCESS-002 | P1 | Interactive controls | verified | Shared tap surfaces relied on `GestureDetector`, omitted keyboard/focus behavior, and inconsistently exposed loading/dismiss state. | Shared controls, app bar, navigation, toast, selection rows | `98b7a40`, `3f1215b` | Controls have keyboard activation, focus, semantic state, minimum targets, stable loading geometry, and passing accessibility guidelines. Onboarding-specific semantics remain ACCESS-001. |
| ACCESS-003 | P1 | Text contrast | verified | Tertiary text at 3.24:1 was used for meaningful 12-14 pt copy and placeholders on white. | Contrast guideline failure and audited role consumers | `3f1215b` | Meaningful secondary copy now uses the existing higher-contrast semantic role; tertiary remains decorative/icon-only. Palette values are unchanged and contrast tests pass. |
| UX-003 | P1 | Button behavior | verified | `CustomButton` fired haptics on pointer-down before an accepted tap, probed capability per press, and lacked deterministic loading semantics. | `custom_button.dart`; haptic service tests | `98b7a40` | One semantic haptic occurs only after an accepted enabled action; disabled/loading controls emit nothing, block duplicates, remain size-stable, and announce progress. |
| UX-004 | P2 | Selection choreography | verified | Wallet and asset selection inserted a fixed post-success delay before navigation and ignored reduced motion. | Wallet selection; asset selector sheet | `98b7a40` | Commit delay resolves through the motion policy and navigation occurs only after confirmed selection success; reduced motion removes decorative delay. |
| ARCH-004 | P1 | Plugin boundary | unreviewed | Scan presentation constructs `ImagePicker` and `MobileScannerController` directly, contrary to the View -> ViewModel -> repository/service boundary. | scan screen/widget import audit | - | Move plugin ownership behind an injectable scanner/media service during the scan/send integration phase; do not hide the gap in Phase 3. |
| NAV-001 | P1 | Bottom navigation | verified | The second bottom-nav item was announced as “Cards” while opening Scan, and the floating nav ignored the persistent bottom hardware inset. | `bottom_nav.dart`; `skeleton_index_provider.dart` | `98b7a40` | Scan label/icon, selection state/haptic, equal stable slots, centered indicator, squircle surface, and persistent bottom inset pass widget regression tests. |
| STORE-008 | P0 | Legacy recovery UX | blocked | Fail-closed legacy-wallet detection presents an explanatory terminal state with no recovery, import, reset, or support action, leaving an existing user unable to proceed. | Exact `3f1215b` iPhone Air launch, legacy secure-store/history audit, and DEC-029 | - | Automatic recovery needs an idempotent per-record migration journal so a crash between new-wallet commit and old-record deletion cannot duplicate or lose a wallet. Product must choose in-app migration or support-assisted recovery; deletion-only reset remains prohibited. |

## Generated Artifact Validation

These files are generated or resolved artifacts and are intentionally excluded
from the hand-review inventory. They must be regenerated or resolved and diffed
through their owning tool.

| Artifact | Owner | Status | Verification |
| --- | --- | --- | --- |
| `pubspec.lock` | Flutter pub | verified | Existing Flutter 3.44.9 and immutable SDK graph remains intact; exact `bs58check` 1.0.2 and `dart_bech32` 2.0.0 resolve with hosted SHA-256 identities and pass aggregate exact-commit gates at `021a610`. |
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
| `assets/data/README.md` | Asset | verified | ONB-003 | Immutable upstream commit, digest, entry count, and SDK checksum-authority boundary recorded | `5f3698f` |
| `assets/data/bip39_english.txt` | Asset | verified | ONB-003 | Exact 2,048-word pinned bytes pass digest/shape/order and tamper tests | `5f3698f`, `05c7edf` |
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
| `docs/PRODUCTION_REFACTOR_TRACKER.md` | Documentation | verified | STORE-008, TEST-001, GIT-001, PAY-001, PAY-003, DEP-005 | Inventory, phase evidence, open constraints, and Bitcoin destination decisions are reconciled to exact implementation and executable gates | `1b3273a`, `3f1215b`, `021a610` |
| `docs/architecture/ARCHITECTURE_GOOGLE_STYLE.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/ARCHITECTURE_SUMMARY.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/BARREL_EXPORTS.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/NETWORK_RELIABILITY.md` | Documentation | verified | NET-001, NET-002, NET-003, LIFE-004 | Retry, timeout, cancellation, reachability, mutation, and native-timeout ownership match implementation/tests | `1b3273a` |
| `docs/architecture/SDK_INTEGRATION.md` | Documentation | verified | SDK-001, DOC-003, LIFE-001, CONFIG-003 | Immutable pin, local override, runtime ownership, adapter boundary, lifecycle, and isolated regtest policy match implementation | `1b3273a` |
| `docs/design/DESIGN_SYSTEM_NORMALIZATION_TRACKER.md` | Documentation | verified | DS-001, DS-002, DS-003, DS-004, ACCESS-003 | Truthful semantic-token contract replaces the stale zero-issue claim and matches audited implementation/tests | `98b7a40`, `3f1215b` |
| `docs/design/DOCSTRING_PATTERNS.md` | Documentation | unreviewed | - | - | - |
| `docs/design/HAPTIC_FEEDBACK.md` | Documentation | verified | UX-001, UX-003 | Semantic intent matrix, no-op rules, ownership, failure isolation, and testing match the implemented service | `98b7a40` |
| `docs/design/PRESENTATION_SYSTEMS.md` | Documentation | verified | UX-001, UX-002, SAFE-001, MOTION-001 | Haptic, toast, inset, loading, and reduced-motion contracts match implementation and tests | `98b7a40` |
| `docs/design/TYPOGRAPHY_USAGE.md` | Documentation | verified | DS-002, ACCESS-003 | DM Sans/Public Sans span ownership and semantic contrast guidance match tested behavior | `3f1215b` |
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
| `lib/core/config/app_environment.dart` | Dart source | fixing | CONFIG-001, CONFIG-002, CONFIG-003 | Existing endpoint policy remains verified; Phase 5 adds all-or-nothing RGB contract/precision validation while real deployment values remain blocked | `1b3273a`, `044a75c` |
| `lib/core/config/config.dart` | Dart source | verified | CONFIG-001 | Boundary barrel exports only app configuration | `1b3273a` |
| `lib/core/constants/app_constants.dart` | Dart source | verified | NET-001 | Reusable timeout/page constants were removed in favor of owned semantic policies; remaining app identity constants reviewed | `1b3273a` |
| `lib/core/constants/constants.dart` | Dart source | verified | ARCH-001 | Barrel no longer exports removed endpoint surface | `1b3273a` |
| `lib/core/constants/storage_keys.dart` | Dart source | verified | STORE-001, SEC-005 | Only versioned, namespaced registry/credential and legacy-detection keys remain | `1b3273a` |
| `lib/core/core.dart` | Dart source | verified | CONFIG-001, SEC-010 | Core boundary exports the reviewed injectable sensitive-clipboard contract without leaking implementation details | `1b3273a`, `05c7edf` |
| `lib/core/di/di.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/providers.dart` | Dart source | fixing | SDK-001, LIFE-001, LIFE-005, SETTINGS-002, ONB-003, SEC-010, PAY-001, PAY-003 | Repository and engine factory share one route-aware Bitcoin instruction decoder through generated Riverpod DI; focused composition tests pass and aggregate verification is pending | `1b3273a`, `6cc7376`, `05c7edf`, `021a610` |
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
| `lib/core/platform/platform.dart` | Dart source | verified | SEC-010 | Boundary exports only the secret-safe clipboard contract and adapter | `05c7edf` |
| `lib/core/platform/sensitive_clipboard_service.dart` | Dart source | verified | SEC-010 | Bounded serialized lease stores only a digest, clears matching content, preserves replacement content, redacts failures, and passes fault/timer/disposal tests | `05c7edf` |
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
| `lib/features/home/presentation/widgets/price_card.dart` | Dart source | verified | ARCH-002, DATA-002, HOME-002 | Consumer widget keeps injected truthful states and bounds loaded title/value layout at phone widths; 390x844 real-router regression passes | `1b3273a`, `518b077` |
| `lib/features/home/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/screens/market_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/widgets/market_tile.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/market/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/onboarding/data/repository/bip39_word_list_repository.dart` | Dart source | verified | DEC-023, ONB-003 | Concurrent bounded load, byte digest, UTF-8/count/order/uniqueness checks, retryable redacted failure, and production/tamper tests pass | `5f3698f`, `05c7edf` |
| `lib/features/onboarding/data/repository/repository.dart` | Dart source | verified | ONB-003 | Feature data boundary exports only the canonical vocabulary repository | `5f3698f` |
| `lib/features/onboarding/domain/models/mnemonic_word_status.dart` | Dart source | verified | ONB-001, ONB-002 | Minimal typed per-word/checksum states are immutable enum values with no wire or UI dependency | `05c7edf` |
| `lib/features/onboarding/domain/models/models.dart` | Dart source | verified | ONB-001 | Domain boundary exports only mnemonic validation state | `05c7edf` |
| `lib/features/onboarding/presentation/models/create_wallet_state.dart` | Dart source | verified | ONB-001, SEC-010 | Immutable route state enforces 12-word and non-overlap invariants and releases phrase references after commit | `05c7edf` |
| `lib/features/onboarding/presentation/models/import_wallet_state.dart` | Dart source | verified | ONB-001, ONB-002, SEC-010 | Immutable route state owns exactly 12 bounded slots, typed checksum state, and submission eligibility | `05c7edf` |
| `lib/features/onboarding/presentation/models/models.dart` | Dart source | verified | ONB-001 | Presentation boundary exports only create/import state | `05c7edf` |
| `lib/features/onboarding/presentation/screens/onboarding_create_wallet_screen.dart` | Dart source | verified | ONB-001, SEC-010, ROUTE-003 | Real generation/copy/provisioning states are accessible and scroll-safe; stack and cold-link Back paths pass | `05c7edf`, `518b077` |
| `lib/features/onboarding/presentation/screens/onboarding_import_wallet_screen.dart` | Dart source | verified | ONB-001, ONB-002, SEC-010, ROUTE-003, DS-005 | Real 12-field/checksum/loading flow is keyboard-, route-, and token-safe across host and native audited paths | `05c7edf`, `518b077` |
| `lib/features/onboarding/presentation/screens/onboarding_welcome_screen.dart` | Dart source | verified | ONB-001, BRAND-001, ACCESS-001 | UTEXO-branded, scroll-safe welcome routes only to real create/import flows and passes compact/large checks | `05c7edf` |
| `lib/features/onboarding/presentation/screens/screens.dart` | Dart source | verified | ONB-001 | Boundary exports welcome, create, and import screens only | `05c7edf` |
| `lib/features/onboarding/presentation/view_model/create_wallet_view_model.dart` | Dart source | verified | ONB-001, SEC-010 | SDK generation, serialized clipboard copy, transactional provisioning, exact registry adoption, result haptics, and failure retention pass tests | `05c7edf` |
| `lib/features/onboarding/presentation/view_model/import_wallet_view_model.dart` | Dart source | verified | ONB-001, ONB-002, ONB-004, SEC-010 | SDK checksum/provisioning, stale-result suppression, and independent character/length normalization pass | `05c7edf`, `518b077` |
| `lib/features/onboarding/presentation/view_model/view_models.dart` | Dart source | verified | ONB-001 | Boundary exports generated create/import notifier APIs without generated files | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart` | Dart source | verified | ONB-001, DS-001, SEC-010 | Generated phrase renders six ordered rows in semantic squircle tiles with bounded text | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart` | Dart source | verified | ONB-002, ACCESS-001, ACCESS-005 | Four-field page owns secure keyboard configuration, one action-preserving editable semantics node per field, squircle fields, bounded formatter, and validity-dependent Next/Done action; host and native trees pass | `05c7edf`, `518b077` |
| `lib/features/onboarding/presentation/widgets/onboarding_status_panel.dart` | Dart source | verified | ONB-001, ACCESS-001 | Shared loading/failure panel is scroll-safe, redacted, retryable, and accessible | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/onboarding_text_action.dart` | Dart source | verified | ONB-001, UX-001, ACCESS-001 | Secondary action owns semantic haptic, disabled state, touch target, and stadium geometry | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_header.dart` | Dart source | verified | BRAND-001 | Visible brand copy says UTEXO while asset renaming remains tracked separately | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_icon_grid.dart` | Dart source | verified | DS-001, DS-005 | Squircle art composition consumes semantic alpha/highlight metrics while retaining its one-off authored pattern | `05c7edf`, `518b077` |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_mesh_background.dart` | Dart source | reviewed-clean | DS-004 | One-off authored mesh control geometry remains local; semantic colors, grid dimensions, blur, and noise effects come from the theme | `05c7edf` |
| `lib/features/onboarding/presentation/widgets/widgets.dart` | Dart source | verified | ONB-001 | Boundary exports only public onboarding widgets, sorted without generated/private leakage | `05c7edf` |
| `lib/features/receive/presentation/screens/receive_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/screens/receive_set_amount_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/widgets/receive_card.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/receive/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/screens/scan_screen.dart` | Dart source | fixing | ARCH-004, SEC-004 | User-visible failures are redacted and feedback is semantic; plugin/service ownership remains Phase 5 | `98b7a40` |
| `lib/features/scan/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/scan_state.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/scan_view_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/view_model/view_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_background.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/scan/presentation/widgets/scan_camera.dart` | Dart source | fixing | ARCH-004, SEC-004 | Raw exception rendering removed; direct scanner-plugin controller ownership remains Phase 5 | `98b7a40` |
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
| `lib/features/settings/data/repository/repository.dart` | Dart source | verified | SETTINGS-002 | Feature data boundary exports only the typed settings repository | `6cc7376` |
| `lib/features/settings/data/repository/settings_repository.dart` | Dart source | verified | DEC-024, SETTINGS-002, SETTINGS-003 | Versioned preferences, serialized writes, bounded catalog loading, canonical identity, self-healing defaults, and redacted failures pass tests | `6cc7376` |
| `lib/features/settings/domain/models/app_preferences.dart` | Dart source | verified | DEC-024 | Typed immutable defaults and persisted identity contract reviewed and restart-tested | `6cc7376` |
| `lib/features/settings/domain/models/fiat_currency.dart` | Dart source | verified | SETTINGS-003 | Immutable ISO identity and display metadata stay app-owned and are catalog-tested | `6cc7376` |
| `lib/features/settings/domain/models/models.dart` | Dart source | verified | SETTINGS-002 | Domain barrel exports only app-owned settings models | `6cc7376` |
| `lib/features/settings/domain/models/region.dart` | Dart source | verified | SETTINGS-002 | Immutable ISO region identity remains independent from display assets | `6cc7376` |
| `lib/features/settings/domain/models/settings_snapshot.dart` | Dart source | verified | DEC-024 | One immutable snapshot joins preferences and validated catalogs for presentation | `6cc7376` |
| `lib/features/settings/presentation/models/models.dart` | Dart source | verified | SETTINGS-002 | Presentation barrel exports only typed immutable screen state | `6cc7376` |
| `lib/features/settings/presentation/models/network_configuration_state.dart` | Dart source | verified | SETTINGS-001, SEC-004 | Network diagnostics expose redacted typed display values and operation-specific health state | `6cc7376` |
| `lib/features/settings/presentation/models/settings_state.dart` | Dart source | verified | DEC-024, SETTINGS-002 | Selection/loading/failure state is immutable and operation-specific | `6cc7376` |
| `lib/features/settings/presentation/screens/advanced_settings_screen.dart` | Dart source | verified | SETTINGS-001, SEC-007, ACCESS-001 | Network diagnostics are reachable; sensitive disclosures are explicitly disabled pending SEC-007 and semantics tests pass | `6cc7376` |
| `lib/features/settings/presentation/screens/bitcoin_unit_selection_screen.dart` | Dart source | verified | SETTINGS-001, ACCESS-001 | Durable selection waits for success, suppresses duplicate mutation, and passes widget/accessibility tests | `6cc7376` |
| `lib/features/settings/presentation/screens/country_selection_screen.dart` | Dart source | verified | DEC-024, FLAG-001 | Region selection consumes typed state and `circle_flags`, persists before pop, and compiles under the full host suite | `6cc7376` |
| `lib/features/settings/presentation/screens/currency_selection_screen.dart` | Dart source | verified | DEC-024, FLAG-001 | Currency selection consumes typed state and `circle_flags`, persists before pop, and compiles under the full host suite | `6cc7376` |
| `lib/features/settings/presentation/screens/network_configuration_screen.dart` | Dart source | reviewed-clean | SETTINGS-001, SEC-004 | Source review confirms redacted endpoint presentation, real health state, and retry ownership; dedicated platform-health evidence remains Phase 6 | `6cc7376` |
| `lib/features/settings/presentation/screens/screens.dart` | Dart source | verified | SETTINGS-001 | Feature screen boundary exports reviewed settings screens only | `6cc7376` |
| `lib/features/settings/presentation/screens/settings_screen.dart` | Dart source | fixing | SETTINGS-001 | Typed persisted values and advanced navigation are wired; app-wide unit consumption and remaining feature rows continue in Phase 5 | `6cc7376` |
| `lib/features/settings/presentation/view_model/network_configuration_view_model.dart` | Dart source | reviewed-clean | SETTINGS-001, SEC-004 | Provider-owned load/retry state maps real configuration and bounded health checks without leaking URL paths | `6cc7376` |
| `lib/features/settings/presentation/view_model/settings_view_model.dart` | Dart source | verified | DEC-024, SETTINGS-002 | Generated AsyncNotifier serializes effective mutations, suppresses overlap, retains prior data on failure, and passes fault tests | `6cc7376` |
| `lib/features/settings/presentation/view_model/view_models.dart` | Dart source | verified | SETTINGS-002 | Presentation boundary exports generated-owner source declarations without exporting generated files | `6cc7376` |
| `lib/features/settings/presentation/widgets/country_select_option_row.dart` | Dart source | verified | FLAG-001, ACCESS-001 | Shared region row uses `circle_flags`, stable selection semantics, and semantic haptic ownership | `6cc7376` |
| `lib/features/settings/presentation/widgets/currency_select_option_row.dart` | Dart source | verified | FLAG-001, ACCESS-001 | Shared currency row uses `circle_flags`, stable selection semantics, and semantic haptic ownership | `6cc7376` |
| `lib/features/settings/presentation/widgets/settings_choice_row.dart` | Dart source | verified | SETTINGS-002, ACCESS-001 | Reusable choice row owns disabled/loading/selected semantics without direct persistence | `6cc7376` |
| `lib/features/settings/presentation/widgets/settings_option_row.dart` | Dart source | verified | SETTINGS-001, ACCESS-001 | Settings navigation row handles long details, disabled state, and accessible labeling without layout overflow | `6cc7376` |
| `lib/features/settings/presentation/widgets/widgets.dart` | Dart source | verified | SETTINGS-002 | Feature widget boundary exports reviewed public settings rows only | `6cc7376` |
| `lib/features/skeleton/presentation/providers/providers.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/providers/skeleton_index_provider.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/skeleton/presentation/screens/skeleton_screen.dart` | Dart source | verified | MOTION-002, NAV-001 | Hidden tabs retain state while tickers, semantics, and pointer input are disabled; widget tests pass | `98b7a40` |
| `lib/features/skeleton/presentation/widgets/bottom_nav.dart` | Dart source | verified | NAV-001, ACCESS-002 | Correct destinations, stable equal slots, centered indicator, semantics, haptics, shape, and bottom inset pass tests | `98b7a40` |
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
| `lib/features/wallet/data/repository/wallet_repository.dart` | Dart source | fixing | SDK-001, LIFE-001, LIFE-003, LIFE-005, WALLET-001, STORE-004, SEC-006, SEC-009, ONB-003, CONFIG-002, DOMAIN-001, PAY-001, PAY-002, PAY-003 | Existing lifecycle paths remain verified; route-specific preview/send now extracts and validates the selected BIP321 instruction before serialized native access, merges only bounded display metadata, and suppresses invalid mutations. Focused tests pass; aggregate verification is pending | `1b3273a`, `5f3698f`, `05c7edf`, `044a75c`, `605b50c`, `021a610` |
| `lib/features/wallet/data/runtime/rgb_wallet_engine.dart` | Dart source | fixing | SDK-001, DOMAIN-002, PAY-001, PAY-002, PAY-003 | Existing native mapping remains verified; the factory shares the narrowed address-validation facet of the route-aware parser and continues to reject invalid native receive/send addresses before mutation. Aggregate verification is pending | `1b3273a`, `605b50c`, `021a610` |
| `lib/features/wallet/data/runtime/runtime.dart` | Dart source | verified | LIFE-001 | Runtime boundary exports only owned interfaces/implementation | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_directory_manager.dart` | Dart source | verified | PLAT-004, SEC-006 | Create/open/collision/rollback ownership semantics pass host and platform tests | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_engine.dart` | Dart source | verified | SDK-001, DOMAIN-002, PAY-002 | App-owned native adapter contract exposes typed balance, receive, preview, send, network, and key shapes only | `1b3273a`, `605b50c` |
| `lib/features/wallet/data/runtime/wallet_identity_generator.dart` | Dart source | verified | SEC-003, SEC-006 | CSPRNG opaque IDs, independent ownership tokens, and 256-bit database secrets pass shape/independence tests | `1b3273a` |
| `lib/features/wallet/data/runtime/wallet_runtime.dart` | Dart source | verified | LIFE-001, LIFE-004, SEC-006, STORE-004 | Single serialization queue, state machine, rollback, quarantine, reinit, disposal, and audit fault matrix passes | `1b3273a` |
| `lib/features/wallet/data/storage/legacy_wallet_seed_preflight.dart` | Dart source | verified | STORE-001, STORE-002 | Legacy seed detection fails closed, preserves evidence, and rechecks non-authoritative outcomes; tests pass | `1b3273a` |
| `lib/features/wallet/data/storage/storage.dart` | Dart source | verified | WALLET-001 | Storage boundary exports reviewed ownership/journal/security contracts only | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_profile_store.dart` | Dart source | verified | WALLET-001, STORE-001, STORE-004, STORE-005, STORE-006, STORE-007 | Versioned decoding, serialized mutation, quarantine, legacy precedence, and monotonic timestamps pass tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_registry_document_store.dart` | Dart source | verified | STORE-003, PLAT-004 | Bounded checksummed two-slot journal and atomic native replacement pass corruption/torn-write tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_secret_store.dart` | Dart source | verified | SEC-005, SEC-006, SEC-009 | Versioned bounded credential envelope, ownership-aware commit/delete, corruption and unknown-outcome handling pass tests | `1b3273a` |
| `lib/features/wallet/data/storage/wallet_storage_security.dart` | Dart source | verified | PLAT-004 | Typed platform-channel policy validates inputs and maps bounded native failures; real platform tests pass | `1b3273a` |
| `lib/features/wallet/data/validation/bitcoin_payment_instruction_parser.dart` | Dart source | fixing | DEC-031, DEC-032, PAY-001, PAY-003, DEP-005 | Parser-owned results, exact integer amounts, Base58Check/Bech32/Bech32m validation, route preservation, BOLT11 extraction, duplicate/required-instruction policy, unsafe-text rejection, and RFC 3986 decoding pass focused vectors; aggregate verification is pending | `021a610` |
| `lib/features/wallet/data/validation/validation.dart` | Dart source | fixing | DEC-031, DEC-032, PAY-001, PAY-003 | Data-layer boundary exports only the app-owned Bitcoin address and route-aware instruction contracts and implementation; aggregate verification is pending | `021a610` |
| `lib/features/wallet/domain/models/models.dart` | Dart source | verified | DEC-013, PAY-002 | Domain boundary exports app-owned network, asset, amount, balance, profile, payment, and portfolio contracts; parser-internal validation results are not exposed here | `1b3273a`, `605b50c` |
| `lib/features/wallet/domain/models/wallet_amount.dart` | Dart source | verified | DEC-013, DOMAIN-002 | Integer smallest-unit/rail/asset invariants and signed-64-bit bounds pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_asset.dart` | Dart source | fixing | DEC-013, DEC-030, DOMAIN-001, PAY-002 | Stable four-route identifiers, product kind, protocol ID/precision, rail, and environment remain separate; route/capability value semantics pass | `1b3273a`, `044a75c`, `605b50c` |
| `lib/features/wallet/domain/models/wallet_balance.dart` | Dart source | verified | DOMAIN-002 | Onchain/Lightning total, available, pending, locked, receivable dimensions use checked integer aggregation; tests pass | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_network.dart` | Dart source | verified | CONFIG-001, DOMAIN-002 | Network status and public-key bounds/value semantics pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_payment.dart` | Dart source | fixing | PAY-001, PAY-002, PAY-003, SEC-004 | Exact-unit contracts and bounded safe recipient label/message metadata preserve route invariants; a copy method merges parsed URI metadata without retaining or printing the source URI. Aggregate verification is pending | `605b50c`, `021a610` |
| `lib/features/wallet/domain/models/wallet_portfolio.dart` | Dart source | verified | DOMAIN-001, PAY-002 | Cross-rail BTC and optional configured-USDT balances enforce product-kind and value invariants | `605b50c` |
| `lib/features/wallet/domain/models/wallet_profile.dart` | Dart source | verified | ARCH-003, SEC-003 | Non-secret immutable metadata, Unicode control rejection, UTC timestamps, and opaque identity pass tests | `1b3273a` |
| `lib/features/wallet/domain/models/wallet_registry.dart` | Dart source | verified | WALLET-001 | Immutable registry invariants, staged/ready/quarantined states, active selection, and equality pass tests | `1b3273a` |
| `lib/features/wallet/presentation/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/models/wallet_state.dart` | Dart source | verified | SDK-001, DEC-012 | Immutable operation-specific state carries domain profiles and typed operation failure; equality reviewed/tested | `1b3273a` |
| `lib/features/wallet/presentation/pages/pages.dart` | Dart source | verified | ROUTE-002 | Wallet presentation boundary exports access and selection pages only | `05c7edf` |
| `lib/features/wallet/presentation/pages/wallet_access_screen.dart` | Dart source | verified | ROUTE-002, ACCESS-001 | Guard gate renders typed loading/failure/retry state while durable wallet state resolves | `05c7edf` |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | Dart source | verified | LIFE-003, UX-004, MOTION-001 | Selection navigates only after confirmed transactional switch; duplicate/selected interactions remain disabled and choreography respects reduced motion | `1b3273a`, `98b7a40` |
| `lib/features/wallet/presentation/view_model/viewmodels.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/wallet_viewmodel.dart` | Dart source | verified | SDK-001, DEC-012, LIFE-003 | Generated AsyncNotifier exposes repository-backed load/switch state, suppresses overlap, and maps typed failures; tests pass | `1b3273a` |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | Dart source | verified | ARCH-003 | Widget consumes domain profile rather than persistence model; strict analysis passes | `1b3273a` |
| `lib/features/wallet/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/main.dart` | Dart source | verified | SEC-002, LIFE-001, LIFE-003, LIFE-005, UX-002 | One bootstrapped container and serialized lifecycle tail own repository resume/suspend/dispose; app-root feedback host is scoped without global mutable state | `1b3273a`, `98b7a40` |
| `lib/shared/feedback/feedback.dart` | Dart source | verified | UX-001, UX-002 | Boundary barrel exports only semantic feedback contracts and scope | `98b7a40` |
| `lib/shared/feedback/feedback_scope.dart` | Dart source | verified | UX-001, UX-002 | Inherited injectable service scope has deterministic ownership and lookup | `98b7a40` |
| `lib/shared/feedback/haptic_feedback_service.dart` | Dart source | verified | UX-001, UX-003 | Semantic adapter caches support, serializes safe dispatch, and swallows plugin failure without blocking actions; tests pass | `98b7a40` |
| `lib/shared/feedback/toast_controller.dart` | Dart source | verified | UX-002 | Bounded FIFO queue, duplicate coalescing, dismissal, and disposal contracts pass deterministic tests | `98b7a40` |
| `lib/shared/feedback/toast_host.dart` | Dart source | verified | UX-002, MOTION-001, SAFE-001 | App-root host serializes display, supports reduced motion, keyboard insets, accessible dismissal, and lifecycle-safe timers | `98b7a40` |
| `lib/shared/feedback/toast_message.dart` | Dart source | verified | UX-002 | Immutable semantic message identity/severity contract reviewed and tested | `98b7a40` |
| `lib/shared/formatting/bitcoin_amount_formatter.dart` | Dart source | verified | SETTINGS-001 | Exact integer sats/BTC formatting, grouping, sign, precision, and unit separation pass boundary tests | `6cc7376` |
| `lib/shared/formatting/bitcoin_unit.dart` | Dart source | verified | SETTINGS-001 | Typed persisted display-unit identity is independent from monetary value and payment rail | `6cc7376` |
| `lib/shared/formatting/formatting.dart` | Dart source | verified | SETTINGS-001 | Shared formatting boundary exports only typed public format contracts | `6cc7376` |
| `lib/shared/layout/layout.dart` | Dart source | verified | SAFE-001 | Boundary barrel exports only typed runtime layout environment | `98b7a40` |
| `lib/shared/layout/window_insets.dart` | Dart source | verified | SAFE-001 | Safe, persistent-system, and keyboard inset semantics are distinct and widget-tested | `98b7a40` |
| `lib/shared/models/asset_model.dart` | Dart source | fixing | DOMAIN-001 | Existing model reviewed; typed asset/rail/environment replacement remains Phase 2 | - |
| `lib/shared/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/motion/motion.dart` | Dart source | verified | MOTION-001 | Boundary barrel exports only the effective animation policy | `98b7a40` |
| `lib/shared/motion/motion_policy.dart` | Dart source | verified | MOTION-001 | Platform/view accessibility settings resolve deterministic effective durations and stable disabled-motion behavior | `98b7a40` |
| `lib/shared/routing/app_router.dart` | Dart source | fixing | ROUTE-001, ROUTE-002, ROUTE-003, SEC-004 | Durable wallet refresh, disposal, cold-link guard, and redacted error behavior pass real-router tests; Phase 5 feature route modeling remains | `1b3273a`, `05c7edf` |
| `lib/shared/routing/route_config.dart` | Dart source | fixing | ROUTE-001, ROUTE-002 | Wallet access and create/import routes are typed and guarded; asset/rail and stable transaction-ID routes remain Phase 5 | `05c7edf` |
| `lib/shared/routing/route_guards.dart` | Dart source | verified | ROUTE-002, ROUTE-003 | Pure durable-state policy and real GoRouter cold-link/live-transition matrix pass | `05c7edf` |
| `lib/shared/routing/route_names.dart` | Dart source | fixing | ROUTE-001, ROUTE-002 | Onboarding route names are normalized; Phase 5 feature names remain | `05c7edf` |
| `lib/shared/routing/route_paths.dart` | Dart source | fixing | ROUTE-001, ROUTE-002 | Onboarding paths are normalized; Phase 5 asset/rail/details paths remain | `05c7edf` |
| `lib/shared/routing/routing.dart` | Dart source | reviewed-clean | ROUTE-001 | Public routing barrel exports only router/config/guard/name/path boundaries | `05c7edf` |
| `lib/shared/screens/animated_splash_screen.dart` | Dart source | verified | DS-004, MOTION-001 | Art geometry and phase timing use semantic tokens; cancellation/disposal and reduced-motion terminal state are reviewed/tested | `98b7a40` |
| `lib/shared/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/screens/splash_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/shared.dart` | Dart source | verified | DS-001, UX-001, UX-002, SAFE-001, MOTION-001 | Shared boundary exports reviewed presentation-system APIs without implementation cycles | `98b7a40` |
| `lib/shared/theme/app_theme.dart` | Dart source | verified | DS-001, DS-003, ACCESS-003 | Material components share semantic colors, contrast-safe type, squircles/capsules, and registered extensions; tests/golden/builds pass | `3f1215b` |
| `lib/shared/theme/theme.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/theme_context.dart` | Dart source | verified | DS-003 | Required extensions fail fast rather than constructing silent fallback token sets; tests pass | `98b7a40` |
| `lib/shared/theme/tokens/art_tokens.dart` | Dart source | verified | DS-004, DS-005 | Reusable splash/brand art geometry plus onboarding highlight/indicator metrics are semantic, immutable, copyable, and lerpable | `98b7a40`, `518b077` |
| `lib/shared/theme/tokens/color_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/component_metrics_tokens.dart` | Dart source | verified | DS-004 | Loader, chart, navigation, control, sheet, and touch-target recipes are separated from spacing | `98b7a40` |
| `lib/shared/theme/tokens/effects_tokens.dart` | Dart source | verified | DS-004, DS-005 | Semantic visual effects include onboarding strong/faint tile alpha roles and pass theme-extension gates | `98b7a40`, `518b077` |
| `lib/shared/theme/tokens/gradient_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/iconography_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/motion_tokens.dart` | Dart source | verified | MOTION-001 | Semantic durations/curves and normalized splash phase intervals are immutable and tested through policy consumers | `98b7a40` |
| `lib/shared/theme/tokens/radius_tokens.dart` | Dart source | verified | DS-001 | Semantic radii include true capsule ownership while squircle geometry is carried by shape APIs | `98b7a40` |
| `lib/shared/theme/tokens/shadow_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/spacing_tokens.dart` | Dart source | verified | SAFE-001, DS-004 | Scale contains spatial decisions only; runtime insets and component geometry were removed to owning systems | `98b7a40` |
| `lib/shared/theme/tokens/state_layer_tokens.dart` | Dart source | verified | DS-004, ACCESS-002 | Disabled/pressed/selected/focus semantic effects are centralized and consumed by shared controls | `98b7a40` |
| `lib/shared/theme/tokens/stroke_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/tokens/type_role_tokens.dart` | Dart source | verified | DS-002, ACCESS-003 | Semantic roles own weight/size/contrast decisions while mixed numeric helpers preserve family boundaries | `3f1215b` |
| `lib/shared/theme/tokens/typography_tokens.dart` | Dart source | verified | FONT-001 | Local DM Sans/Public Sans role contract reviewed and theme interpolation passes | `8e97370` |
| `lib/shared/theme/typography.dart` | Dart source | verified | FONT-001 | Runtime font download removed; exact local families and numeric helper build on both platforms | `8e97370` |
| `lib/shared/widgets/amount_text.dart` | Dart source | verified | DS-002 | Integer/mixed amount rendering assigns Public Sans only to numeric spans and inherits semantic UI styling elsewhere; tests pass | `98b7a40` |
| `lib/shared/widgets/app_skeletonizer.dart` | Dart source | verified | MOTION-001 | Shimmer respects reduced motion and preserves truthful loading geometry | `98b7a40` |
| `lib/shared/widgets/asset_display.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_divider.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_icon_button.dart` | Dart source | verified | ACCESS-002, UX-001 | Semantic labels, focus, target size, state layers, and haptic intent are centralized | `98b7a40` |
| `lib/shared/widgets/aster_pill.dart` | Dart source | verified | DS-001 | True stadium geometry is encapsulated for pill-only surfaces | `98b7a40` |
| `lib/shared/widgets/custom_app_bar.dart` | Dart source | verified | ACCESS-002 | Back action uses shared labeled keyboard-operable icon control with semantic haptic | `98b7a40` |
| `lib/shared/widgets/custom_button.dart` | Dart source | verified | DS-001, ACCESS-002, ACCESS-004, UX-003, MOTION-001 | Shared semantic boundary owns the enabled tap action while preserving keyboard/focus, loading stability, duplicate suppression, haptics, and reduced motion; host and Android native actions pass | `98b7a40`, `3f1215b`, `518b077` |
| `lib/shared/widgets/custom_radio.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_toast.dart` | Dart source | verified | UX-002, ACCESS-002, MOTION-001 | Declarative semantic toast surface has no global overlay ownership and exposes accessible state/dismissal; tests pass | `98b7a40` |
| `lib/shared/widgets/detail_row.dart` | Dart source | verified | DS-002, ACCESS-003 | Mixed values use numeric spans without restyling units/labels; meaningful metadata meets semantic contrast | `3f1215b` |
| `lib/shared/widgets/grid_loader.dart` | Dart source | verified | DS-004, MOTION-001 | Geometry/effects are token-owned; ticker lifecycle and stable reduced-motion frame pass tests | `98b7a40` |
| `lib/shared/widgets/squircle.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/widgets.dart` | Dart source | verified | DS-001, DS-002, ACCESS-002 | Shared widget boundary exports reviewed public components without private/generated implementation leakage | `98b7a40` |
| `pubspec.yaml` | Project configuration | verified | BASE-001, SDK-001, DEP-001, DEP-002, DEP-003, DEP-004, DEP-005, FONT-001, FLAG-001 | Immutable SDK/dependency policy and exact direct MIT Bitcoin codec primitives pass resolution, source/license review, official vectors, and aggregate gates | `1b3273a`, `6cc7376`, `021a610` |
| `scripts/git-hooks/pre-commit` | Tooling | verified | BUILD-002 | Non-mutating quality gate executes successfully | `8e97370` |
| `scripts/install-git-hooks.sh` | Tooling | unreviewed | - | - | - |
| `test/core/bootstrap/app_bootstrap_test.dart` | Test | verified | LIFE-002, LIFE-005 | Partial-construction cleanup and composed unknown-outcome failures pass | `1b3273a` |
| `test/core/bootstrap/app_loader_test.dart` | Test | verified | LIFE-002, SEC-004 | Redacted retryable and unknown-outcome bootstrap widget states pass | `1b3273a` |
| `test/core/config/app_environment_test.dart` | Test | fixing | CONFIG-001, CONFIG-002, CONFIG-003 | Existing endpoint matrix plus RGB identity/precision validation pass; real deployment values remain blocked | `1b3273a`, `044a75c` |
| `test/core/di/providers_test.dart` | Test | verified | LIFE-001 | Keep-alive async repository composition remains mounted | `1b3273a` |
| `test/core/errors/failure_mapper_test.dart` | Test | verified | DEC-012, SEC-004, SEC-008 | SDK/HTTP/storage/protocol taxonomy, redaction, retry, and unknown-outcome matrix passes | `1b3273a` |
| `test/core/network/resilient_http_client_test.dart` | Test | verified | NET-001, NET-002, NET-003 | Retry/budget/abort/cancel/redirect/body/scheme/policy fault matrix passes | `1b3273a` |
| `test/core/platform/sensitive_clipboard_service_test.dart` | Test | verified | SEC-010 | Matching clear, replacement preservation, expiry, disposal drain, and redacted platform-failure cases pass | `05c7edf` |
| `test/features/home/bitcoin_market_repository_test.dart` | Test | verified | DATA-002 | Integer mapping, sorting, deduplication, fallback, freshness, bounds, and malformed-data cases pass | `1b3273a` |
| `test/features/home/bitcoin_market_view_model_test.dart` | Test | verified | ARCH-002 | Duplicate retry is suppressed while initial request is active | `1b3273a` |
| `test/features/onboarding/bip39_word_list_repository_test.dart` | Test | verified | ONB-003 | Production asset, tampered bytes, canonical membership, retry, and concurrent cache behavior pass | `5f3698f`, `05c7edf` |
| `test/features/onboarding/onboarding_screens_test.dart` | Test | verified | ONB-001, ONB-002, ACCESS-001, ACCESS-005 | Real fields/paste/loading/copy/keyboard/carousel plus merged editable semantics actions, compact/large/text-scale/accessibility behavior pass | `05c7edf`, `518b077` |
| `test/features/onboarding/onboarding_view_models_test.dart` | Test | verified | ONB-001, ONB-003, ONB-004, SEC-010 | Character/length normalization, checksum, overlap, stale completion, copy, provision, failure, and secret-release paths pass | `05c7edf`, `518b077` |
| `test/features/settings/settings_repository_test.dart` | Test | verified | DEC-024, SETTINGS-002, SETTINGS-003 | Defaults, persistence across reconstruction, invalid/corrupt repair, serialization, redaction, and production catalog invariants pass | `6cc7376` |
| `test/features/settings/settings_screens_test.dart` | Test | verified | SETTINGS-001, SEC-007, ACCESS-001 | Durable unit interaction and disabled sensitive-disclosure accessibility behavior pass | `6cc7376` |
| `test/features/settings/settings_view_model_test.dart` | Test | verified | DEC-024, SETTINGS-002 | Overlapping settings mutations are suppressed and state remains coherent | `6cc7376` |
| `test/features/wallet/bitcoin_payment_instruction_parser_test.dart` | Test | fixing | DEC-032, PAY-001, PAY-003, DEP-005 | Official BIP173/BIP350 vectors plus Base58, regtest, BIP321 rail selection, repeated instructions, exact amount, RFC 3986 decoding, duplicate/required/range, and display-attack cases pass in the focused 67-test matrix | `021a610` |
| `test/features/wallet/rgb_wallet_engine_test.dart` | Test | verified | SDK-001, DOMAIN-002, PAY-001, PAY-002 | Existing SDK/payment vectors remain green; checksum-valid native receive/send, wrong-network/checksum rejection, and pre-mutation suppression pass | `1b3273a`, `605b50c`, `021a610` |
| `test/features/wallet/wallet_domain_models_test.dart` | Test | fixing | DEC-013, DEC-030, DOMAIN-001, DOMAIN-002, PAY-002 | Existing invariants plus payment target, exact-unit contract, equality, route resolution, availability, and portfolio vectors pass | `1b3273a`, `044a75c`, `605b50c` |
| `test/features/wallet/wallet_identity_generator_test.dart` | Test | verified | SEC-003, SEC-006 | CSPRNG output length, alphabet, uniqueness, and secret size pass | `1b3273a` |
| `test/features/wallet/wallet_repository_test.dart` | Test | fixing | WALLET-001, LIFE-003, STORE-004, SEC-006, SEC-009, ONB-003, CONFIG-002, DOMAIN-001, PAY-001, PAY-002, PAY-003 | Existing lifecycle/payment matrix plus local on-chain preview, BIP321 normalization/amount consistency, selected Lightning extraction, invalid-input mutation suppression, and queue ordering pass; aggregate verification is pending | `1b3273a`, `5f3698f`, `05c7edf`, `044a75c`, `605b50c`, `021a610` |
| `test/features/wallet/wallet_runtime_test.dart` | Test | verified | LIFE-001, LIFE-004, SEC-006, STORE-004 | Runtime ordering, rollback, quarantine, reinit, cleanup, audit, and disposal matrix passes | `1b3273a` |
| `test/features/wallet/wallet_storage_test.dart` | Test | verified | SEC-005, STORE-001, STORE-002, STORE-003, STORE-005, STORE-006, STORE-007 | Credential, journal, corruption, ownership, legacy, collision, and timestamp matrix passes | `1b3273a` |
| `test/features/wallet/wallet_viewmodel_test.dart` | Test | verified | DEC-012, LIFE-003 | Initial loading overlap suppression passes | `1b3273a` |
| `test/goldens/presentation_components.png` | Test | verified | DS-001, DS-002, ACCESS-003 | 390x844 approved rendering was generated with bundled UI, numeric, and package icon fonts and visually inspected | `3f1215b` |
| `test/goldens/presentation_components_golden_test.dart` | Test | verified | DS-001, DS-002, ACCESS-002, ACCESS-003 | Golden plus Android target-size, labeled-target, and contrast guidelines pass | `3f1215b` |
| `test/shared/app_router_test.dart` | Test | verified | ROUTE-002, ROUTE-003, HOME-002 | Real GoRouter cold-link, persisted-active, safe-Back, live-provision transition, and loaded home-width regressions pass | `518b077` |
| `test/shared/bitcoin_amount_formatter_test.dart` | Test | verified | SETTINGS-001 | Exact integer BTC/sats formatter boundaries, signs, grouping, and no-precision-loss cases pass | `6cc7376` |
| `test/shared/feedback_system_test.dart` | Test | verified | UX-001, UX-002, UX-003 | Haptic support caching/failure isolation and bounded toast ordering/deduplication/disposal matrix passes | `98b7a40` |
| `test/shared/presentation_system_test.dart` | Test | verified | DS-001, DS-002, DS-003, ACCESS-004, MOTION-001, NAV-001, SAFE-001 | Theme failure, inset semantics, numeric spans, shape types, native button tap-action ownership, reduced motion, navigation geometry, and toast host tests pass | `98b7a40`, `518b077` |
| `test/shared/route_guards_test.dart` | Test | verified | ROUTE-002 | Pure unresolved/empty/active route matrix passes | `05c7edf` |
| `test/support/onboarding_harness.dart` | Test | verified | TEST-001, ONB-001 | Deterministic real repository/runtime composition disables automatic test retries and permits bounded injected market transport | `05c7edf`, `518b077` |
| `test/support/wallet_fakes.dart` | Test | verified | TEST-001, PAY-002 | Deterministic test-only fakes record typed payment arguments, expose operation gates/faults, and cannot enter release code | `1b3273a`, `605b50c` |
| `test/widget_test.dart` | Test | verified | TEST-001, MOTION-002 | Root presentation wiring and hidden-tab ticker/semantics behavior pass; broader feature coverage remains tracked independently | `98b7a40` |
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
