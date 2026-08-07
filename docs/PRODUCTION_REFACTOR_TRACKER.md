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

## Phase Plan

| Phase | Scope | Status | Exit evidence |
| --- | --- | --- | --- |
| 0 | Inventory, baseline, tracker, decisions, and audit tooling | verified | Inventory validator, baseline evidence, all files classified. |
| 1 | Flutter/Dart pin, dependency resolution, analysis, generation, fonts, CI, and platform baseline | fixing | Clean format/analyze/test/doc plus iOS and Android compile. |
| 2 | Domain architecture, SDK lifecycle, repositories, models, error/result policy, networking, storage, and security | unreviewed | Unit/contract/fault tests and lifecycle evidence. |
| 3 | Design system and shared UX systems | unreviewed | Token audit, accessibility/widget/golden tests, reduced-motion behavior. |
| 4 | Onboarding and settings | unreviewed | Create/import/restart/unit/advanced end-to-end evidence. |
| 5 | Home, send, receive, swap, activity, and transaction details | unreviewed | Truthful four-rail flows and integration/widget evidence. |
| 6 | Documentation, performance, memory, platform hardening, and release evidence | unreviewed | Exact-candidate release report with measurements and constraints. |
| 7 | Independent file-by-file closeout | unreviewed | Zero unreviewed files and zero untracked non-accepted findings. |

## Findings

| ID | Severity | Area | Status | Finding | Evidence | Fix commit | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BASE-001 | P0 | Toolchain | fixing | Flutter 3.38.9 / Dart 3.10.8 cannot consume the SDK, which requires Flutter 3.41+ / Dart 3.11+. | `.fvmrc`, `pubspec.yaml`, SDK `pubspec.yaml` | - | - |
| SDK-001 | P0 | Integration | unreviewed | The app has no `rgb_sdk_flutter` dependency or app-owned SDK lifecycle owner. | `pubspec.yaml`; source inventory | - | - |
| DATA-001 | P0 | Product truth | unreviewed | Production UI presents static/mock balances, prices, activity, wallet identifiers, addresses, and delayed loading behavior. | Baseline runtime and source search | - | - |
| SEND-001 | P0 | Send | unreviewed | Send opens directly on a form prefilled with a sample Bitcoin address and has no asset/rail selection or real submission. | Baseline Send screenshot | - | - |
| ONB-001 | P0 | Onboarding | unreviewed | Create is not implemented; import is not backed by BIP39/SDK lifecycle behavior and exposes incomplete semantics. | Baseline Welcome/Import screenshots and accessibility snapshot | - | - |
| LIFE-001 | P0 | Lifecycle | unreviewed | No single serialized owner exists for native wallet init, unlock, sync, reinit, shutdown, and destroy. | Source inventory | - | - |
| SEC-001 | P0 | Logging | unreviewed | The HTTP logging interceptor can emit request/response bodies and sensitive native/network material. | `lib/core/network/interceptors/logging_interceptor.dart` | - | - |
| PLAT-001 | P0 | Platform identity | blocked | Android/iOS use `com.example` identifiers and Android release uses debug signing. | Platform build files; DEC-006 | - | - |
| TEST-001 | P0 | Testing | unreviewed | The repository has one test file with two token assertions and no behavioral, platform, integration, accessibility, golden, lifecycle, or performance coverage. | Baseline test run | - | - |
| BUILD-001 | P1 | Android | blocked | Baseline Android build could not download Gradle and therefore did not compile. | Baseline `flutter build apk --debug` timeout | - | Retry after toolchain/dependency phase. |
| DOC-001 | P1 | Documentation | unreviewed | Architecture and setup material describe Aster/GDK/Boltz/Liquid-era concepts instead of the target UTEXO SDK architecture. | `README.md`, `docs/architecture/` | - | - |
| DOC-002 | P2 | API docs | unreviewed | `dart doc` emits two unresolved `[enableLogging]` references. | Baseline dartdoc output | - | - |
| DEP-001 | P1 | Dependencies | unreviewed | Direct constraints are stale, `intl` is unconstrained, and discontinued transitive packages remain. | Baseline `flutter pub outdated` | - | - |
| FLAG-001 | P2 | Assets/dependencies | unreviewed | `circle_flags`, `country_flags`, and `flag` coexist despite one required flag implementation. | `pubspec.yaml` and settings/send imports | - | - |
| FONT-001 | P1 | Determinism | unreviewed | UI typography relies on `google_fonts` rather than bundled exact DM Sans and Public Sans assets. | Theme source and `pubspec.yaml` | - | - |
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

## Generated Artifact Validation

These files are generated or resolved artifacts and are intentionally excluded
from the hand-review inventory. They must be regenerated or resolved and diffed
through their owning tool.

| Artifact | Owner | Status | Verification |
| --- | --- | --- | --- |
| `pubspec.lock` | Flutter pub | unreviewed | Resolve on the pinned Flutter toolchain and review dependency graph. |
| `ios/Podfile.lock` | CocoaPods / Flutter | unreviewed | Resolve after SDK and platform changes; build exact candidate. |
| `lib/objectbox-model.json` | ObjectBox generator | unreviewed | Regenerate and validate model IDs. |
| `**/*.g.dart` | build_runner generators | unreviewed | Regenerate with delete-conflicting-outputs and require a clean second run. |
| `**/*.freezed.dart` | Freezed generator | unreviewed | Regenerate with delete-conflicting-outputs and require a clean second run. |
| `ios/.spm.pods/**` | CocoaPods SwiftPM bridge | unreviewed | Determine whether generated content should remain tracked. |

## File Review Inventory

The inventory is mechanically checked by
`dart run tool/verify_production_tracker.dart`. Findings still require a real
line-by-line review; inventory synchronization is not evidence of correctness.

<!-- FILE_INVENTORY_START -->
| File | Kind | Status | Finding IDs | Verification | Fix commit |
| --- | --- | --- | --- | --- | --- |
| `.envrc` | Project configuration | unreviewed | - | - | - |
| `.fvmrc` | Project configuration | unreviewed | - | - | - |
| `.github/workflows/dart.yml` | CI | unreviewed | - | - | - |
| `.gitignore` | Project configuration | unreviewed | - | - | - |
| `.metadata` | Project configuration | unreviewed | - | - | - |
| `.vscode/settings.json` | Project configuration | unreviewed | - | - | - |
| `Makefile` | Project configuration | unreviewed | - | - | - |
| `README.md` | Project configuration | unreviewed | - | - | - |
| `analysis_options.yaml` | Project configuration | unreviewed | - | - | - |
| `android/.gitignore` | Android platform | unreviewed | - | - | - |
| `android/app/build.gradle.kts` | Android platform | unreviewed | - | - | - |
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
| `android/gradle.properties` | Android platform | unreviewed | - | - | - |
| `android/gradle/wrapper/gradle-wrapper.properties` | Android platform | unreviewed | - | - | - |
| `android/settings.gradle.kts` | Android platform | unreviewed | - | - | - |
| `assets/brand/aster-logo.svg` | Asset | unreviewed | - | - | - |
| `assets/brand/banner.svg` | Asset | unreviewed | - | - | - |
| `assets/data/countries.json` | Asset | unreviewed | - | - | - |
| `assets/data/currencies.json` | Asset | unreviewed | - | - | - |
| `assets/icons/images/bitcoin.png` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/btc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/lbtc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdc.svg` | Asset | unreviewed | - | - | - |
| `assets/icons/tokens/usdt.svg` | Asset | unreviewed | - | - | - |
| `assets/texture/noise.jpg` | Asset | unreviewed | - | - | - |
| `assets/texture/shape.png` | Asset | unreviewed | - | - | - |
| `devtools_options.yaml` | Project configuration | unreviewed | - | - | - |
| `docs/DEVELOPMENT.md` | Documentation | unreviewed | - | - | - |
| `docs/PRODUCTION_REFACTOR_TRACKER.md` | Documentation | verified | - | Inventory validator and Markdown review | Phase 0 commit |
| `docs/architecture/ARCHITECTURE_GOOGLE_STYLE.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/ARCHITECTURE_SUMMARY.md` | Documentation | unreviewed | - | - | - |
| `docs/architecture/BARREL_EXPORTS.md` | Documentation | unreviewed | - | - | - |
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
| `ios/Podfile` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.pbxproj` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | iOS platform | unreviewed | - | - | - |
| `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | iOS platform | unreviewed | - | - | - |
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
| `lib/core/bootstrap/app_loader.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/api_endpoints.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/app_constants.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/constants.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/constants/storage_keys.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/core.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/di.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/modules/modules.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/modules/network_module.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/modules/storage_module.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/di/providers.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/error_handler.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/errors.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/exceptions.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/failures.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/errors/result_type.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/interceptors/auth_interceptor.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/interceptors/error_interceptor.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/interceptors/interceptors.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/interceptors/logging_interceptor.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/network.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/network/network_info.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/database_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/preferences_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/secure_storage_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/storage/storage.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/extensions/string_extensions.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/formatters.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/utils.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/validators.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/wallet_id_generator.dart` | Dart source | unreviewed | - | - | - |
| `lib/core/utils/wallet_migration_service.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/home/data/bitcoin_price_service.dart` | Dart source | unreviewed | - | - | - |
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
| `lib/features/wallet/data/models/wallet_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/repository/repository.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/repository/wallet_repository.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/data/repository/wallet_repository_impl.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/models/wallet_state.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/pages/pages.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/viewmodels.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/view_model/wallet_viewmodel.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/features/wallet/presentation/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `lib/main.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/asset_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/country_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/currency_model.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/models/models.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/routing/app_router.dart` | Dart source | unreviewed | - | - | - |
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
| `lib/shared/theme/tokens/typography_tokens.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/theme/typography.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/amount_text.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/app_skeletonizer.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/asset_display.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/aster_divider.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_app_bar.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_button.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_radio.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/custom_toast.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/detail_row.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/grid_loader.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/squircle.dart` | Dart source | unreviewed | - | - | - |
| `lib/shared/widgets/widgets.dart` | Dart source | unreviewed | - | - | - |
| `pubspec.yaml` | Project configuration | unreviewed | - | - | - |
| `scripts/git-hooks/pre-commit` | Tooling | unreviewed | - | - | - |
| `scripts/install-git-hooks.sh` | Tooling | unreviewed | - | - | - |
| `test/widget_test.dart` | Test | unreviewed | - | - | - |
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
