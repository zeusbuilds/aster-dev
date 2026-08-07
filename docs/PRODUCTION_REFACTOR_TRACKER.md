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
- Current phase: Phase 1, toolchain and project foundation
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

## Phase Plan

| Phase | Scope | Status | Exit evidence |
| --- | --- | --- | --- |
| 0 | Inventory, baseline, tracker, decisions, and audit tooling | verified | Inventory validator, baseline evidence, all files classified. |
| 1 | Flutter/Dart pin, dependency resolution, analysis, generation, fonts, CI, and platform baseline | verified | Clean format/analyze/test/doc plus iOS and Android compile. |
| 2 | Domain architecture, SDK lifecycle, repositories, models, error/result policy, networking, storage, and security | unreviewed | Unit/contract/fault tests and lifecycle evidence. |
| 3 | Design system and shared UX systems | unreviewed | Token audit, accessibility/widget/golden tests, reduced-motion behavior. |
| 4 | Onboarding and settings | unreviewed | Create/import/restart/unit/advanced end-to-end evidence. |
| 5 | Home, send, receive, swap, activity, and transaction details | unreviewed | Truthful four-rail flows and integration/widget evidence. |
| 6 | Documentation, performance, memory, platform hardening, and release evidence | unreviewed | Exact-candidate release report with measurements and constraints. |
| 7 | Independent file-by-file closeout | unreviewed | Zero unreviewed files and zero untracked non-accepted findings. |

## Findings

| ID | Severity | Area | Status | Finding | Evidence | Fix commit | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BASE-001 | P0 | Toolchain | verified | Flutter 3.38.9 / Dart 3.10.8 could not consume the SDK, which requires Flutter 3.41+ / Dart 3.11+. | `.fvmrc`, `pubspec.yaml`, SDK `pubspec.yaml` | Phase 1 implementation commit | Flutter 3.44.9 / Dart 3.12.2 gates and both platform builds pass. |
| SDK-001 | P0 | Integration | fixing | The immutable public `rgb_sdk_flutter` dependency is integrated, but the app-owned `UtexoWallet` lifecycle owner and repository adapters do not exist yet. | `pubspec.yaml`; source inventory | Phase 1 implementation commit | Dependency resolved and both platform builds pass; lifecycle work remains in Phase 2. |
| DATA-001 | P0 | Product truth | unreviewed | Production UI presents static/mock balances, prices, activity, wallet identifiers, addresses, and delayed loading behavior. | Baseline runtime and source search | - | - |
| SEND-001 | P0 | Send | unreviewed | Send opens directly on a form prefilled with a sample Bitcoin address and has no asset/rail selection or real submission. | Baseline Send screenshot | - | - |
| ONB-001 | P0 | Onboarding | unreviewed | Create is not implemented; import is not backed by BIP39/SDK lifecycle behavior and exposes incomplete semantics. | Baseline Welcome/Import screenshots and accessibility snapshot | - | - |
| LIFE-001 | P0 | Lifecycle | unreviewed | No single serialized owner exists for native wallet init, unlock, sync, reinit, shutdown, and destroy. | Source inventory | - | - |
| SEC-001 | P0 | Logging | verified | The unused HTTP logging interceptor could emit request/response bodies and sensitive native/network material. | `lib/core/network/interceptors/logging_interceptor.dart` | Phase 1 implementation commit | Dead Chopper/interceptor surface and dependencies removed; repository search and fatal analysis pass. A production logging policy is still required in Phase 2. |
| PLAT-001 | P0 | Platform identity | blocked | Android/iOS use `com.example` identifiers and Android release uses debug signing. | Platform build files; DEC-006 | - | - |
| TEST-001 | P0 | Testing | unreviewed | The repository has one test file with two token assertions and no behavioral, platform, integration, accessibility, golden, lifecycle, or performance coverage. | Baseline test run | - | - |
| BUILD-001 | P1 | Android | verified | Baseline Android build could not download Gradle and therefore did not compile. | Baseline `flutter build apk --debug` timeout | Phase 1 implementation commit | Exact current-candidate x86_64 debug APK packages successfully; artifact hash is recorded above. |
| DOC-001 | P1 | Documentation | unreviewed | Architecture and setup material describe Aster/GDK/Boltz/Liquid-era concepts instead of the target UTEXO SDK architecture. | `README.md`, `docs/architecture/` | - | - |
| DOC-002 | P2 | API docs | verified | `dart doc` emitted two unresolved `[enableLogging]` references. | Baseline dartdoc output | Phase 1 implementation commit | `dart doc --validate-links` completes with zero warnings and zero errors. |
| DOC-003 | P1 | Development setup | verified | Development instructions described removed import tools, non-fatal analysis, Flutter 3.38, and referenced no SDK override contract. | `docs/DEVELOPMENT.md`; `pubspec.yaml` comment | Phase 1 implementation commit | Guide now matches executable Make/CI gates and documents a non-committed local SDK override. |
| DEP-001 | P1 | Dependencies | verified | Direct constraints were stale, `intl` was unconstrained, and unused architecture packages remained direct dependencies. | Baseline `flutter pub outdated`; consumer searches | Phase 1 implementation commit | Direct dependencies were deliberately upgraded or removed; compatibility pins are recorded in DEC-007 and DEC-008. |
| DEP-002 | P2 | SDK dependency graph | blocked | Discontinued transitive package `js` 0.7.2 remains through `pointycastle` 3.9.1, which is constrained by the immutable SDK dependency. | `flutter pub deps`; SDK `pubspec.yaml` | - | Requires a future SDK revision that supports pointycastle 4 or removes that dependency; do not override the pinned SDK graph in the app. |
| FLAG-001 | P2 | Assets/dependencies | unreviewed | `circle_flags`, `country_flags`, and `flag` coexist despite one required flag implementation. | `pubspec.yaml` and settings/send imports | - | - |
| FONT-001 | P1 | Determinism | verified | UI typography relied on `google_fonts` rather than bundled exact DM Sans and Public Sans assets. | Theme source and `pubspec.yaml` | Phase 1 implementation commit | Exact variable fonts and OFL licenses are bundled with recorded provenance/checksums; iOS and Android builds pass offline font registration. |
| NET-001 | P1 | Reliability | unreviewed | The network layer lacks a uniform timeout, idempotent retry/backoff, failure taxonomy, and safe observability policy. | `lib/core/network/` | - | - |
| UX-001 | P1 | Shared UX | unreviewed | Haptics are called directly from widgets with repeated capability probes and no semantic/testable policy owner. | Haptic import/call search | - | - |
| UX-002 | P1 | Shared UX | unreviewed | Toasts are not owned by a queued/deduplicated service and at least one flow still uses `SnackBar`. | Toast/SnackBar search | - | - |
| ACCESS-001 | P1 | Accessibility | unreviewed | Baseline semantics include empty/duplicated labels and omit editable mnemonic fields. | Xcode runtime accessibility snapshots | - | - |
| ROUTE-001 | P1 | Routing | unreviewed | Current routes do not model asset/rail flow state or transaction details by stable ID. | Routing source inventory | - | - |
| HOME-001 | P1 | Home | unreviewed | The visibility control is not wired or persisted; asset rows do not represent BTC/RGB aggregate balances from real data. | Baseline Home and source | - | - |
| RECV-001 | P1 | Receive | unreviewed | Receive has no asset/rail selection or real invoice lifecycle and includes obsolete Direct Peg In behavior. | Baseline Receive and source | - | - |
| SWAP-001 | P1 | Swap | unreviewed | Swap assets do not match the target domain and execution must be made explicitly unavailable without simulating success. | Swap source; CON-002 | - | - |
| TX-001 | P1 | Activity | unreviewed | There is no normalized cross-rail activity model or transaction-details route/screen. | Transaction source inventory | - | - |
| SETTINGS-001 | P1 | Settings | unreviewed | Bitcoin unit and required advanced wallet/network settings are absent or placeholders. | Baseline Settings and source | - | - |
| SAFE-001 | P2 | Layout | unreviewed | Safe-area helpers and call sites have not been validated against `padding`, `viewPadding`, keyboard `viewInsets`, and double inset behavior. | Design tokens and UI source | - | - |
| PERF-001 | P1 | Performance | unreviewed | No measured launch, frame, memory, leak, rebuild, cache, or SDK-handle baseline exists. | Test/tooling inventory | - | - |
| SEC-002 | P0 | Seed security | verified | Two hardcoded 12-word mnemonics were compiled into the app, printed around migration activity, and written to secure storage at startup. | `lib/core/utils/wallet_migration_service.dart`; `lib/main.dart` | Phase 1 implementation commit | Migration and startup writes removed; repository search contains no mnemonic fixture or logging path. |
| SEC-003 | P0 | Seed privacy | verified | Legacy wallet identity and display name were deterministically derived directly from mnemonic text, creating a stable seed fingerprint outside the SDK lifecycle. | `wallet_id_generator.dart`; legacy `wallet_model.dart` | Phase 1 implementation commit | Seed-derived generator removed; replacement `WalletProfile` accepts only an opaque post-SDK wallet ID and non-secret metadata. |
| GIT-001 | P1 | Delivery | blocked | The repository-local Zeus commit succeeds, but origin rejects the active Jainakin credential with `Repository not found`. | Push of `163a3cf` | - | Restore project-scoped Zeus access; do not change global identity or remote. |
| BUILD-002 | P1 | Code generation | verified | The original Riverpod 2.4 generator used analyzer 6.4, which only understood Dart 3.4 while the app now uses Dart 3.12. | Baseline Phase 1 build-runner warning | Phase 1 implementation commit | Riverpod 3.3.2 / generator 4.0.4 resolves analyzer 12.1; generation completes without a language-version warning. |
| ARCH-001 | P1 | Networking/DI | verified | Unused Chopper clients, duplicate interceptors, and no-op DI modules exposed stale APIs and an unsafe body logger. | Consumer search found definitions only | Phase 1 implementation commit | Removed the dead Chopper surface and dependency; fatal analyzer is clean. |
| PLAT-002 | P2 | Android toolchain | blocked | Flutter 3.44 warns that the app and `haptic_feedback`, `mobile_scanner`, and `rgb_sdk_flutter` apply the legacy Kotlin Gradle plugin, which a future Flutter release will reject. | Exact Android build output | - | App migration requires Flutter 3.47+; plugin owners must also publish built-in Kotlin support. Current AGP 9.0.1/Kotlin 2.3.20 build passes with Flutter-generated compatibility flags. |
| SDK-002 | P2 | iOS packaging | blocked | The pinned `rgb_sdk_flutter` revision does not support Swift Package Manager, which Flutter warns will become mandatory in a future release. | Exact iOS simulator build output | - | CocoaPods integration passes now; resolve in a future immutable SDK revision before Flutter removes fallback support. |
| TOOL-001 | P2 | Build environment | verified | Host disk exhaustion interrupted the first exact Android APK packaging attempt after compilation. | `:app:packageDebug` `No space left on device` | - | Removed only disposable caches and local build output; identical candidate build passed without touching protected regtest, simulator/emulator, source, or user data. |
| TOOL-002 | P3 | iOS simulator | blocked | iOS 26.5 logs duplicate `UIAccessibilityLoaderWebShared` implementations from its WebCore and WebKit accessibility bundles during launch. | Exact Phase 1 runtime log for process 45978 | - | This originates inside the Apple simulator runtime, not the app bundle. Recheck on a future simulator runtime and physical device; no app exception accompanied it. |
| SEC-004 | P0 | Error privacy | unreviewed | Route errors and generic HTTP/exception handling can expose raw exception strings or response bodies to users and diagnostics. | `app_router.dart`; `error_handler.dart` | - | Replace with typed, redacted diagnostics plus stable user-safe messages in Phase 2. |
| LIFE-002 | P0 | Bootstrap | unreviewed | App initialization has no typed failure state or recovery path; an exception can leave a blank app under an indefinitely visible splash. | `app_loader.dart::_load` | - | Add explicit bootstrap state, redacted failure UI, retry, and cancellation-safe ownership in Phase 2. |
| ARCH-002 | P1 | MVVM boundary | unreviewed | `PriceCard` calls a static HTTP service directly and owns request state, violating View -> ViewModel -> Repository/service flow and preventing injection. | `price_card.dart`; `bitcoin_price_service.dart` | - | Move transport behind an injected repository and generated AsyncNotifier with typed refresh/error state in Phase 2. |
| WALLET-001 | P0 | Wallet metadata | unreviewed | The temporary SharedPreferences wallet registry uses unsynchronized read-modify-write operations and does not integrate corruption recovery or native lifecycle transactions. | `wallet_repository.dart` | - | Serialize mutations under the single runtime owner, expose typed failures, and test concurrent/corrupt/restart behavior in Phase 2. |
| DOMAIN-001 | P0 | Asset model | unreviewed | `AssetModel` still represents asset and chain with display strings and cannot model Bitcoin/RGB USDT independently from onchain/Lightning rail and blockchain environment. | `asset_model.dart`; send/receive/swap call sites | - | Replace with app-owned typed asset ID, payment rail, and environment models using integer smallest units in Phase 2. |

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
| `.fvmrc` | Project configuration | verified | BASE-001 | Flutter 3.44.9 installed and all Phase 1 gates pass | Phase 1 implementation commit |
| `.github/workflows/dart.yml` | CI | verified | BASE-001, BUILD-002 | Pinned toolchain, generation, fatal analysis, tests, and tracker gates reviewed | Phase 1 implementation commit |
| `.gitignore` | Project configuration | unreviewed | - | - | - |
| `.metadata` | Project configuration | verified | BASE-001 | Flutter migration metadata matches framework revision `6b182d2c` and owned platforms | Phase 1 implementation commit |
| `.vscode/settings.json` | Project configuration | verified | BASE-001 | Project-local Flutter SDK path points to 3.44.9 | Phase 1 implementation commit |
| `Makefile` | Project configuration | verified | BUILD-002 | Commands executed locally; lint target is non-mutating and passes | Phase 1 implementation commit |
| `README.md` | Project configuration | fixing | DOC-001 | Broken dartdoc-style local links removed; product rewrite remains in Phase 6 | Phase 1 implementation commit |
| `analysis_options.yaml` | Project configuration | verified | BUILD-002, ARCH-001 | Strict inference/casts/raw types and lifecycle/future/security lints pass with zero diagnostics | Phase 1 implementation commit |
| `android/.gitignore` | Android platform | unreviewed | - | - | - |
| `android/app/build.gradle.kts` | Android platform | fixing | BUILD-001, PLAT-001, PLAT-002 | AGP 9 / Java 17 / SDK 36 x86_64 APK build passes; release identity/signing and future Kotlin migration remain open | Phase 1 implementation commit |
| `android/app/src/debug/AndroidManifest.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/AndroidManifest.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/kotlin/com/example/asterdev/MainActivity.kt` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/drawable-v21/launch_background.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/drawable/launch_background.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/values-night/styles.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/main/res/values/styles.xml` | Android platform | unreviewed | - | - | - |
| `android/app/src/profile/AndroidManifest.xml` | Android platform | unreviewed | - | - | - |
| `android/build.gradle.kts` | Android platform | unreviewed | - | - | - |
| `android/gradle.properties` | Android platform | fixing | PLAT-002 | Flutter-generated AGP 9 compatibility flags build; built-in Kotlin migration remains blocked on toolchain/plugins | Phase 1 implementation commit |
| `android/gradle/wrapper/gradle-wrapper.properties` | Android platform | verified | BUILD-001 | Gradle 9.1.0 matches Flutter 3.44 template and packages exact APK | Phase 1 implementation commit |
| `android/settings.gradle.kts` | Android platform | fixing | BUILD-001, PLAT-002 | AGP 9.0.1/Kotlin 2.3.20 compile; future built-in Kotlin migration tracked | Phase 1 implementation commit |
| `assets/brand/aster-logo.svg` | Asset | unreviewed | - | - | - |
| `assets/brand/banner.svg` | Asset | unreviewed | - | - | - |
| `assets/data/countries.json` | Asset | unreviewed | - | - | - |
| `assets/data/currencies.json` | Asset | unreviewed | - | - | - |
| `assets/fonts/DMSans-Italic-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | Phase 1 implementation commit |
| `assets/fonts/DMSans-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | Phase 1 implementation commit |
| `assets/fonts/LICENSE-DM-SANS.txt` | Asset | verified | FONT-001 | Upstream OFL license bundled and reviewed | Phase 1 implementation commit |
| `assets/fonts/LICENSE-PUBLIC-SANS.txt` | Asset | verified | FONT-001 | Upstream OFL license bundled and reviewed | Phase 1 implementation commit |
| `assets/fonts/PublicSans-Italic-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | Phase 1 implementation commit |
| `assets/fonts/PublicSans-Variable.ttf` | Asset | verified | FONT-001 | SHA-256 and pinned upstream provenance recorded; platform builds pass | Phase 1 implementation commit |
| `assets/fonts/README.md` | Asset | verified | FONT-001 | Source commit, role ownership, hashes, and replacement policy reviewed | Phase 1 implementation commit |
| `assets/icons/images/bitcoin.png` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/btc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/lbtc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdt.svg` | Asset | unreviewed | - | - | - |
| `assets/texture/noise.jpg` | Asset | unreviewed | - | - | - |
| `assets/texture/shape.png` | Asset | unreviewed | - | - | - |
| `devtools_options.yaml` | Project configuration | unreviewed | - | - | - |
| `docs/DEVELOPMENT.md` | Documentation | verified | DOC-003 | Commands, toolchain, CI, and local SDK workflow match executable configuration | Phase 1 implementation commit |
| `docs/PRODUCTION_REFACTOR_TRACKER.md` | Documentation | verified | - | Inventory validator and Markdown review | Phase 0 commit |
| `docs/architecture/ARCHITECTURE_GOOGLE_STYLE.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/ARCHITECTURE_SUMMARY.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/BARREL_EXPORTS.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/SDK_INTEGRATION.md` | Documentation | verified | SDK-001, DOC-003 | Immutable pin, optional uncommitted path override, ownership boundary, and release constraint documented | Phase 1 implementation commit |
| `docs/design/DESIGN_SYSTEM_NORMALIZATION_TRACKER.md` | Documentation | unreviewed | - | - | - |
| `docs/design/DOCSTRING_PATTERNS.md` | Documentation | unreviewed | - | - | - |
| `docs/design/HAPTIC_FEEDBACK.md` | Documentation | unreviewed | - | - | - |
| `docs/design/TYPOGRAPHY_USAGE.md` | Documentation | unreviewed | - | - | - |
| `docs/release/evidence/baseline/ios-home-bbbc315.jpg` | Documentation | reviewed-clean | HOME-001, DATA-001 | Captured from exact baseline commit on iPhone Air | Phase 0 commit |
| `docs/release/evidence/baseline/ios-import-bbbc315.jpg` | Documentation | reviewed-clean | ONB-001, ACCESS-001 | Captured from exact baseline commit on iPhone Air | Phase 0 commit |
| `docs/release/evidence/baseline/ios-receive-bbbc315.jpg` | Documentation | reviewed-clean | RECV-001 | Captured from exact baseline commit on iPhone Air | Phase 0 commit |
| `docs/release/evidence/baseline/ios-send-bbbc315.jpg` | Documentation | reviewed-clean | SEND-001, DATA-001 | Captured from exact baseline commit on iPhone Air | Phase 0 commit |
| `docs/release/evidence/baseline/ios-welcome-bbbc315.jpg` | Documentation | reviewed-clean | ONB-001 | Captured from exact baseline commit on iPhone Air | Phase 0 commit |
| `flake.lock` | Project configuration | unreviewed | - | - | - |
| `flake.nix` | Project configuration | unreviewed | - | - | - |
| `ios/.gitignore` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/AppFrameworkInfo.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/Debug.xcconfig` | iOS platform | unreviewed | - | - | - |
| `ios/Flutter/Release.xcconfig` | iOS platform | unreviewed | - | - | - |
| `ios/Podfile` | iOS platform | fixing | SDK-001, SDK-002, PLAT-001 | SDK-required iOS 18.5 deployment passes exact simulator build; identity and future SwiftPM support remain open | Phase 1 implementation commit |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS platform | fixing | SDK-001, SDK-002, PLAT-001 | Flutter migration diff reviewed and exact simulator launch passes; identity remains unresolved | Phase 1 implementation commit |
| `ios/Runner.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | iOS platform | verified | SDK-002 | Flutter-generated prepare-framework action reviewed; CocoaPods simulator build passes | Phase 1 implementation commit |
| `ios/Runner.xcworkspace/contents.xcworkspacedata` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | iOS platform | unreviewed | - | - | - |
| `ios/Runner/AppDelegate.swift` | iOS platform | unreviewed | - | - | - |
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
| `lib/core/bootstrap/app_loader.dart` | Dart source | fixing | LIFE-002 | Container disposal reviewed; typed bootstrap failure/retry and cancellable reveal remain Phase 2 | - |
| `lib/core/constants/api_endpoints.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/app_constants.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/constants.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/storage_keys.dart` | Dart source | fixing | SEC-002, SEC-003, SDK-001 | Seed key API removed; temporary non-secret profile key remains pending lifecycle integration | Phase 1 implementation commit |
| `lib/core/core.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/di.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/providers.dart` | Dart source | fixing | ARCH-001, SDK-001 | Dead Chopper/ObjectBox providers removed and generated async dependencies pass; SDK runtime providers remain Phase 2 | Phase 1 implementation commit |
| `lib/core/errors/error_handler.dart` | Dart source | fixing | NET-001, SEC-004 | Raw exception/body leakage identified; replacement taxonomy remains Phase 2 | - |
| `lib/core/errors/errors.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/exceptions.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/failures.dart` | Dart source | fixing | NET-001 | Dynamic generation removed and strict analysis passes; final typed SDK/network taxonomy remains Phase 2 | Phase 1 implementation commit |
| `lib/core/errors/result_type.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/network.dart` | Dart source | fixing | ARCH-001, NET-001 | Unsafe dead interceptors removed; replacement reliability layer remains Phase 2 | Phase 1 implementation commit |
| `lib/core/network/network_info.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/preferences_service.dart` | Dart source | reviewed-clean | ARCH-001 | API and async persistence forwarding reviewed; strict analysis passes | Phase 1 implementation commit |
| `lib/core/storage/secure_storage_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/storage.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/extensions/string_extensions.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/formatters.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/utils.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/validators.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/data/bitcoin_price_service.dart` | Dart source | fixing | NET-001 | Fake fallback and logging removed; direct static HTTP ownership/retry/error taxonomy remain Phase 2 | Phase 1 implementation commit |
| `lib/features/home/data/data.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/data/models/chart_data_item.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/screens/home_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/screens/screens.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/asset_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/assets_section.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/candle_chart.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/home_action_buttons.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/home_header.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/mesh_gradient_background.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/presentation/widgets/price_card.dart` | Dart source | unreviewed | - | - | - |
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
| `lib/features/wallet/data/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/models/wallet_model.dart` | Dart source | fixing | SEC-003, SDK-001 | Seed-derived ObjectBox model replaced by non-secret metadata; app domain naming/lifecycle adapter remains Phase 2 | Phase 1 implementation commit |
| `lib/features/wallet/data/repository/repository.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/repository/wallet_repository.dart` | Dart source | fixing | SEC-002, SEC-003, SDK-001 | Seed persistence removed; temporary versioned metadata registry reviewed, with serialization/lifecycle integration remaining Phase 2 | Phase 1 implementation commit |
| `lib/features/wallet/presentation/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/models/wallet_state.dart` | Dart source | fixing | SDK-001 | Immutable operation-specific switch state introduced; final SDK-backed state remains Phase 2 | Phase 1 implementation commit |
| `lib/features/wallet/presentation/pages/pages.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/viewmodels.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/wallet_viewmodel.dart` | Dart source | fixing | SDK-001 | Generated AsyncNotifier removes build-time microtask and logs; SDK-backed lifecycle switching remains Phase 2 | Phase 1 implementation commit |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/main.dart` | Dart source | fixing | SEC-002, LIFE-001 | Hardcoded seed migration removed; single SDK runtime owner and lifecycle handling remain Phase 2 | Phase 1 implementation commit |
| `lib/shared/models/asset_model.dart` | Dart source | fixing | DOMAIN-001 | Existing model reviewed; typed asset/rail/environment replacement remains Phase 2 | - |
| `lib/shared/models/country_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/currency_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/app_router.dart` | Dart source | fixing | ROUTE-001, SEC-004 | Raw route diagnostics and placeholder guards identified; Phase 2/5 routing work remains | - |
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
| `lib/shared/theme/tokens/typography_tokens.dart` | Dart source | verified | FONT-001 | Local DM Sans/Public Sans role contract reviewed and theme interpolation passes | Phase 1 implementation commit |
| `lib/shared/theme/typography.dart` | Dart source | verified | FONT-001 | Runtime font download removed; exact local families and numeric helper build on both platforms | Phase 1 implementation commit |
| `lib/shared/widgets/amount_text.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/app_skeletonizer.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/asset_display.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_divider.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_app_bar.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_radio.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_toast.dart` | Dart source | fixing | UX-002 | Timer/controller disposal corrected; global helper still requires queued injectable service in Phase 3 | Phase 1 implementation commit |
| `lib/shared/widgets/detail_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/grid_loader.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/squircle.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `pubspec.yaml` | Project configuration | verified | BASE-001, SDK-001, DEP-001, DEP-002, FONT-001, FLAG-001 | Public SDK pin, compatible constraints, direct-consumer audit, and assets reviewed; external/transitional findings remain tracked | Phase 1 implementation commit |
| `scripts/git-hooks/pre-commit` | Tooling | verified | BUILD-002 | Non-mutating quality gate executes successfully | Phase 1 implementation commit |
| `scripts/install-git-hooks.sh` | Tooling | unreviewed | - | - | - |
| `test/widget_test.dart` | Test | fixing | TEST-001 | Existing assertions pass on new toolchain; meaningful test expansion remains open | Phase 1 implementation commit |
| `tool/verify_production_tracker.dart` | Tooling | verified | - | Format, sync, clean verification pass, and diff check | Phase 0 commit |
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
