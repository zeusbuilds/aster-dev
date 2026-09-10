# Aster Visual Restoration Tracker

## Reference And Contract

- Approved reference: `bbbc315634bba975ed767de378ff155e08a0ba15`.
- Starting implementation: `5c4a738`.
- Reference screenshots: `~/Desktop/Aster-UI-Baseline-bbbc315`.
- Restore the author's visual language across current screens and flows:
  full-width brand mesh; price/chart Home; spacious two-line asset rows;
  softly outlined squircles; grouped option rows; pill actions; floating nav.
- Preserve current repositories, ViewModels, security boundaries, integer
  amounts, real SDK behavior, visibility, units, validation, and navigation.
- Preserve palette values, DM Sans UI text, and Public Sans numeric spans.
- Historical obsolete asset names and unsupported financial behavior are not
  visual requirements. Existing release blockers remain in
  `docs/PRODUCTION_REFACTOR_TRACKER.md`.
- Use only the dedicated Aster simulator. Iris simulators and the protected
  regtest stack belong to other tasks.
- Screenshots of deterministic test fixtures must be labeled as UI evidence,
  never native payment or funding proof.

## Phases

### Author Refinement: White Onboarding And No Tap Ink

2026-09-10: the author's current request supersedes the historical glass/mesh
recovery styling and VIS-011/VIS-023's earlier transparent-button solution.
Only Welcome keeps the mesh; Create/Import are real separate routes with white
surfaces and dark content. Copy/Back/Import text actions use plain tappable
content with keyboard/semantic parity, not TextButton. Tap ink is disabled in
the app theme and Material component state policy on both platforms. Focus,
hover, custom button scale, haptics, real wallet operations, palette values,
fonts, and layout content are preserved. Active implementation verification is
tracked as UXA-016, UXA-017, and DS-021 in the production tracker.

The follow-up author decision keeps the Aster mark and wordmark only at the top
of the blue Welcome screen. Create and Import begin directly with their existing
titles on white; all recovery content, geometry, controls, state, and behavior
remain unchanged. Verification is tracked as UXA-018.

| Phase | Scope | Status | Verification / commit |
| --- | --- | --- | --- |
| V1 | Shared geometry, controls, Home, shell | verified | 2f522c8 plus native QA corrections; Home/reference compared; full host suite passes |
| V2 | Send, Receive, Swap, selection, sheets | verified | All four rails and sheets captured; QR payload decode 4/4; real behavior preserved |
| V3 | Onboarding, wallet access, settings, activity, scanner, market | verified | 143 source/boundary rows reviewed; 24 real-font onboarding checks; native catalog reviewed |
| V4 | Independent visual audit, responsive tests, iOS screenshots of all screens and states | verified | 94 iOS-engine PNGs reviewed; 883 local tests, Linux tests/golden/contrast and exact platform CI pass at 7798642 |

## Findings

| ID | Status | Evidence and required correction | Verification |
| --- | --- | --- | --- |
| VIS-001 | verified | Home asset rows split content into competing equal-width columns and repeat available balance. Restore the original name/unit and total/fiat hierarchy while preserving availability in activity details and accessibility. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-002 | verified | Home price/header horizontal insets differ, chart/error states change hero composition, and floating nav is wider than the reference. Align Home geometry to the approved reference with responsive expansion. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-003 | verified | Destination/amount cards use independent top/bottom shapes with differing outlines; Paste and Max have drifted into primary action styling. Restore one coherent card boundary and contextual compact controls. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-004 | verified | Current Receive request uses a different QR/action composition. Restore the QR card and grouped action rows, retaining truthful request expiry and generation states. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-005 | verified | New screens need the same outlined groups, alignment, insets, type hierarchy, and responsive behavior as the original components. Review every row below. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-006 | verified | Screenshots must cover every route, four-rail payment variants, sheets, loading/error/empty states, keyboard behavior, and compact/large layouts. Label fixtures and unsupported states honestly. | 2f522c8 / 1b79465; local suite and iOS catalog pass. |
| VIS-007 | verified | Compact pills expanded under loose constraints and changed width while loading. Preserve content sizing and stable loading geometry; make the full 48px hit target interactive without duplicate haptics. | Added geometry, edge-tap, loading and haptic regression checks. |
| VIS-008 | verified | Split-card children could overpaint outlines, while clipping could cut shadows. Shared Squircle now paints background/shadows outside child clipping and the outline in the foreground. | Foreground shape/theme test; rendered catalog review. |
| VIS-009 | verified | Settings chevrons and DetailRow values drifted inward for short values; inset dividers were asymmetric. Reserve a stable trailing column and equal divider insets. | Shared trailing-edge regression. |
| VIS-010 | verified | Recovery wordmark was reduced to label size; generated words could truncate with large type. Restore semantic 40px wordmark, recovery field shape and untruncated words. The initial bottom-anchored import was subsequently corrected by author direction in VIS-024. | 23 initial onboarding tests pass; VIS-024 verifies the revised field/footer anchoring. |
| VIS-011 | verified | Small recovery text over the brightest glass/mesh failed contrast. Use a semantic glass-content scrim from existing palette and opaque number labels. | Automated contrast checks pass at phone and compact scaled sizes. |
| VIS-012 | verified | Send amount entered in sats was labeled BTC. Display the formatter's denomination, keeping asset identity distinct. | Four-rail amount screenshots and payment tests. |
| VIS-013 | verified | Wallet-unavailable container swallowed Retry semantics; route error used an inconsistent, non-scrolling layout. Keep explicit child semantics, shared app bar and scrollable safe-area recovery. | Shared/widget suite and catalog. |
| VIS-014 | verified | Linux presentation golden needs the actual reviewed engine raster for the intentional shadow/outline change. | Reviewed actual Linux raster in 1b79465; golden passes in CI run 34322501973, without tolerance relaxation. |
| VIS-015 | verified | Import controllers hydrate only on subsequent provider changes, so a remounted valid form can show empty fields with green checks. Hydrate the owned controllers immediately when subscribing. | Native catalog discovered; remount regression added. |
| VIS-016 | verified | Hidden/short balances drift left; accessibility-sized Home commands and option-row values truncate or split words. Keep trailing alignment and reflow when text no longer fits. | Native and compact screenshots; geometry regressions. |
| VIS-017 | verified | Toasts outside a route's Material inherit the debug fallback text decoration. Establish a transparent Material text environment inside the shared toast. | Native four-variant screenshots and text-style regression. |
| VIS-018 | verified | Catalog reused cached activity state, mislabeled carousel pages, and retained a debug banner. Assert each intended state before capturing; distinguish simulated keyboard insets from native keyboard evidence. | Host and final 94-image iOS-engine catalog pass at 7798642; images inspected. |
| VIS-019 | verified | Linux onboarding contrast histogram mistakes two mesh background colors for text. Real fonts corrected the wordmark case but two body labels still fail the naive histogram. Independently measure resolved text against every live backdrop pixel under those labels at 4.5:1; retain the standard check for other labels and add failing contrast controls. | All 24 onboarding tests, four checker controls, and full 883-test suite pass locally; Linux Test step passes in run 34324442536 at 7798642. No palette or threshold changes. |
| VIS-020 | verified | Standalone Market/Settings/Scan screenshots do not show their persistent-shell context. Capture actual navigation taps to all three tabs, assert the selected destination, and retain both embedded and standalone views. Explicitly isolate the shell scanner using its test-only session, not the platform camera. | Host and 94-image iOS-engine catalog pass at 7798642; all three shell images inspected full-size. No production code change. |
| VIS-021 | verified | The 94-scene native run passed widget assertions but iOS window capture returned 94 identical launch images. Reject the batch. Capture the actual mounted Flutter layer on the iOS engine, dispose image handles, and verify distinct Home/hidden/Market/Settings hashes before accepting an export. | 7798642 produces 94 captures with 91 distinct rasters; identical loading/non-scrolling states are intentional. Six contact sheets reviewed; four QR payloads independently decoded. OS/platform views explicitly excluded. |

## Independent UI/UX Audit

Date: 2026-09-09. Audited application commit:
`1fe2c1f84b18a4da4e58884885185cd0abec2e2c`.

**Audit verdict: keep the restored design; do not sign off the UI/UX yet.**
The audit identified 15 corrections: 3 P1 and 12 P2. All 15 code defects are
now corrected and host-verified as recorded in Implementation Closeout below;
the three recommendations are explicitly out of scope. Physical qualification
remains outstanding. The original evidence below is the baseline, not
implementation verification.
The historical file-review statuses and VIS findings elsewhere in this document
describe the prior restoration pass only. A prior `verified` or `reviewed-clean`
file can have a new finding below.

### Scope And Evidence

- Read the feature screens, their UI components, shared controls, navigation,
  typography/color/layout contracts, motion and feedback ownership. Followed
  relevant ViewModel contracts where needed to distinguish visual behavior from
  repository/SDK limitations. This is a UI/UX review, not a new SDK/security audit.
- Inspected all six contact sheets of the current 94-scene iOS-engine catalog,
  including all four Send/Receive routes and loading, failure, expired, empty,
  submitting, selector, settings, transaction and shell variants. This is the
  existing capture batch corresponding to the audited source, not a fresh device
  walkthrough. Older contact sheets with superseded UI were excluded.
- Re-ran 200 existing UI, presentation, feedback, routing and catalog tests:
  **200 passed**. This is not a rerun of the historical full 887-test suite.
- Final strict `fvm flutter analyze` passes with no issues. `git diff --check`
  passes. The production-tracker schema validator passes for 574 owned files
  and its existing 415 findings; the 15 UXA corrections are separately counted
  in this linked visual-audit backlog, not included in that validator's total.
- Added 11 local diagnostic probes using bundled DM Sans/Public Sans. All
  completed. Some deliberately assert the presence of a defect; their passing
  result is reproduction evidence, **not** a clean regression gate.
- Probe source: `build/ui-ux-audit/probe_test.dart`; output:
  `/tmp/aster-ui-ux-probes.log`. Existing-test output:
  `/tmp/aster-ui-ux-audit-tests.log`. Contact sheets:
  `build/ui-ux-audit/contact/`. These ignored/local artifacts are not committed
  release evidence and may be removed by cleaning the workspace.
- No production Dart, platform code, palette, fonts, SDK, wallet data or backend
  was changed. No emulator or protected regtest resource was started or modified.
- The dedicated Aster simulator was shut down. Permission to boot it was requested
  but not received during this pass; no other task's device was used. Native OS
  keyboard, camera and physical assistive-technology behavior are not newly proved.

### Correction Baseline

The following table preserves the original defects and requested corrections.
The subsequent Implementation Closeout records actual fixes and verification;
these are also formal UXA findings in the production tracker. Palette primitives
and authored gradient recipes have not changed. Physical assistive-technology
evidence remains a separate verification limitation.

| ID | Priority | Finding / affected behavior | Evidence | Required correction and closure |
| --- | --- | --- | --- | --- |
| UXA-001 | P1 | Enabled Home wallet selector, Home asset rows, Market actions and Swap selectors lose their screen-reader activation action. | `home_header.dart:50`, `asset_row.dart:88`, `market_tile.dart:68`, `swap_pair.dart:24`: `excludeSemantics: true` discards the inner InkWell semantics without an outer `onTap`. Probes return `SemanticsAction.tap == false` for all four components. | Expose one explicit accessible activation through the same enabled/command/haptic path as a pointer tap, or retain correctly merged child actions. Test semantic action dispatch, disabled/loading behavior and keyboard activation, not labels alone. |
| UXA-002 | P1 | Amount entry can conceal significant digits before submission. | `send_card.dart:60` restricts input to one line with clipping. At 320x568 and 2x text, `0.12345678` needs 282.68 logical px but receives 115.45 px. `receive_amount_sheet.dart:209` has the same one-line pattern with ellipsis. The underlying amount remains longer than what is visible. | Give monetary input a shared responsive layout that preserves access to the entire exact amount, including its fractional tail. Reflow the asset/unit or provide an accessible horizontally scrollable editing surface; do not silently abbreviate, round or suppress user text scaling. Test valid BTC/USDT extremes and both units in Send and Receive. |
| UXA-003 | P1 | Generated recovery words have the wrong assistive reading order. | `onboarding_import_wallet_word_grid.dart:18` builds rows containing words 1/7, 2/8, etc. The actual semantic label is `1, word1, 7, word7, 2, word2, 8, word8, ...`. | Preserve the approved six-left/six-right visual layout, but group each numbered word and provide explicit semantic traversal from 1 through 12. Test the emitted semantic order and verify it with VoiceOver/TalkBack. Never change the phrase itself or expose it to logs. |
| UXA-004 | P2 | Changing tabs destroys screen-local state despite IndexedStack. | `app_shell_screen.dart:43` alternates between a screen widget and an ExcludeSemantics wrapper. The probe scrolls Settings to 150 px, switches away/back, and observes a different ScrollableState at offset 0. | Keep a stable wrapper tree and vary `excluding`, `ignoring` and TickerMode properties. Test scroll retention and scanner mount/disposal behavior across repeated tab switches; do not remove offscreen suppression. |
| UXA-005 | P2 | Transaction amounts do not share a trailing alignment edge. | `transaction_item.dart:115` uses a loose Flexible for the amount after an Expanded leading section. At 390 px, amounts of 1 and 100,000,000 sats end 99.98 and 22.48 px before the row edge respectively. `TextAlign.end` only aligns inside that smaller loose child. | Give the value a bounded trailing slot that reaches the row edge, with deliberate reflow for long values. Assert equal right edges for short, long, hidden, pending and Lightning rows at normal/large text. |
| UXA-006 | P2 | A remounted Send address form can show a blank field while its ViewModel still contains a destination. | `send_address_screen.dart:28,107`: an empty controller is synchronized only on later provider changes. A retained populated provider mounts with state `bcrt1qexample` and empty field text. The Continue eligibility reads state rather than the visible controller. This test demonstrates hydration, not validity of that placeholder address. | Hydrate on subscription immediately, reconcile target changes, and keep one ownership rule for editing, scanner handoff and paste. Add a remount test with a fully valid address and assert that visible text and the destination used for validation agree. |
| UXA-007 | P2 | Status colors are used as text colors where they do not have enough contrast. | `aster_status_message.dart:50`, `_StatusBadge` in `transaction_details_screen.dart:434`, and health text in `network_configuration_screen.dart:95`. Actual token contrast on containers: success 2.51:1, warning 2.41:1, danger 3.25:1; on white: 2.78:1, 2.57:1, 3.71:1 respectively. | Preserve palette values. Separate status accents/backgrounds from readable semantic status foregrounds, reusing an existing dark foreground where appropriate. Check inline errors, expiry notices, health labels and badges against their actual surfaces with normal-text contrast tests. |
| UXA-008 | P2 | Active Market tiles have insufficient text contrast; the issue is not limited to disabled tiles. | `market_tile.dart:118,121,148`, `type_role_tokens.dart:294`, `gradient_tokens.dart:124`. Even fully opaque white contrasts only 2.40:1 to 3.60:1 against the Receive gradient endpoints. Labels/tips further reduce white to 75% opacity; tips also sit on a lightened capsule. The enabled Receive tile therefore cannot meet 4.5:1 across its text area. | Retain the authored gradient colors/art and composition. Use a readable existing foreground or a narrowly scoped semantic contrast treatment beneath text. Measure actual rendered text/backdrops, including Send, instead of assuming white-on-color is accessible. Disabled controls are not used as the basis for this finding. |
| UXA-009 | P2 | Max is permanently disabled with no local explanation. | `send_card.dart:136` renders an inert Max pill. The existing SEND-002 blocker requires a truthful fee-aware SDK quote and an honest explanation; the latter is absent from this restored screen. | Keep Max disabled until the real quote contract exists. Explain the limitation near the control or with an accessible discoverable explanation, including fixed-amount invoices where appropriate. This UI fix must not invent a send-max calculation. |
| UXA-010 | P2 | A generated Receive screen drops important payment context. | `receive_request_screen.dart:184,270`: the heading identifies the asset but not the rail; the ready card shows QR/request/amount but no visible rail or future expiry. On-chain and Lightning Bitcoin requests look effectively the same to a user who cannot decode the string. | Keep the selected rail visible and show the actual expiry where the model provides one. Use consistent asset/rail terminology across selection, request, copy/share and expired states. Do not invent expiry for an address without one. |
| UXA-011 | P2 | An expired invoice remains prominently scannable. | `_RequestBody` always builds ReceiveRequestQr before checking expiry. The expired catalog scene retains the intact QR while only copy/share are disabled and a small warning is added. Another device can still scan that expired request. | Replace or clearly invalidate the code surface once expired, while retaining necessary context and a regenerate action. Test the expiry boundary and foreground resume with the injectable clock; verify that a stale payment QR is no longer presented as usable. |
| UXA-012 | P2 | The amount in the Receive action group uses the wrong font. | `receive_request_screen.dart:320` passes `appliedAmount.text` to AsterOptionRow.details; `aster_option_row.dart:81` renders it with ordinary Text/rowValue. The QR-card amount above correctly uses AmountText, so the same value has two different numeric treatments. | Add a typed monetary/detail-content contract to the shared row, retaining layout measurement and semantics. Use Public Sans only for numeric spans; do not indiscriminately apply the numeric font to identifiers, units or all option values. |
| UXA-013 | P2 | A pending transaction has no in-place refresh affordance, and retained-feed refresh failures are invisible when the record exists. | `transaction_details_screen.dart:89,122`: refreshing/refreshFailure are handled only when the ID is absent. The normal CustomScrollView has no RefreshIndicator or refresh control. ActivityViewModel.refresh exposes both progress and retained-data failure. | Allow an explicit idempotent refresh with stale content retained, visible progress and inline failure/retry. Handle all three states even when the record exists. Test a pending-to-confirmed update and a failed refresh without making the user leave/re-enter details. |
| UXA-014 | P2 | Scanner manual-entry target is smaller than the app/Android minimum. | `scan_enter_address_button.dart:36` sizes its InkWell from text plus padding without the shared minimum constraint. The measured target is 390x44 logical px at normal type. It meets the common iOS 44-point guideline, but not the app's 48px target contract or Flutter's Android guideline. | Preserve the text-only visual style and apply the shared minimum interactive height. Assert edge taps and both platform target guidelines, including the destination-picker version. |
| UXA-015 | P2 | Toast dismissal is not adapted to assistive reading. | `toast_host.dart:50,59` always counts down the configured duration; the default is 3 seconds in `motion_tokens.dart:11`. Only app backgrounding pauses the timer. Accessible navigation and accessibility focus do not affect it, although up to 80 title and 240 message characters are accepted. | Define a testable accessibility-aware presentation lifetime and focus/dismissal policy. Keep persistent errors on-screen. Test long messages, queue advancement, reduced motion, background/resume and accessibility settings; validate announcements on devices rather than claiming timer tests prove screen-reader usability. |

References above are relative to feature `presentation/screens` or
`presentation/widgets` and shared `widgets`, `feedback`, or `theme/tokens` as
appropriate. They refer to the audited commit, not future edited line numbers.

Normal-size text is evaluated against the 4.5:1 guidance in
[W3C Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
Touch targets and assistive interaction follow
[Flutter accessibility guidance](https://docs.flutter.dev/ui/accessibility).
These thresholds are applied to functional text/actions, not decorative art.

### Baseline Flow Review

The Remaining work column records the audit baseline. UXA code defects are
resolved by the closeout below; native/external constraints remain open.

| Flow | What is sound in the reviewed scope | Remaining work |
| --- | --- | --- |
| Startup / welcome | Existing brand mesh, splash ownership, safe-area failure recovery and reduced-motion policy are retained. | Native cold-start/foreground timing still needs a fresh device pass; host results do not establish frame pacing. |
| Create wallet | Approved header/background, plain icon/text Copy, numbered two-column words, operation-owned Continue and explicit failures. | UXA-003; physical-device privacy/clipboard/haptic checks remain separate. |
| Import wallet | Fields follow the explanatory text; free space belongs before the footer. Lowercase validation, paged focus and current-screen submission remain. | No new defect reproduced in the manual-swipe focus probe. Actual OS keyboard/accessibility traversal remains unverified here. |
| Home / wallet selector | Original price/chart hero, equal pill actions, two-line assets, persistent balance-visibility and honest missing-price states. | UXA-001 and shell retention UXA-004. |
| Send, four targets | Asset/rail selection, typed validation, explicit fee/balance retries and current-screen submission states are present. | UXA-002, UXA-006, UXA-007, UXA-009. No new funded-send proof in this pass. |
| Receive, four targets | Real request state, amount sheet, conditional amount requirement, copy/share/generation gating and expiry timer are present. | UXA-002, UXA-007, UXA-010, UXA-011, UXA-012. |
| Swap | Four supported target choices and an explicit unavailable execution state; no fabricated success. | UXA-001 for selection; real execution remains CON-002, not a styling fix. |
| Market | Content-height tiles and approved decorative texture/gradient composition match the latest direction. | UXA-001 and UXA-008. |
| Activity / details | Cross-rail rows, Lightning marker, stable ID routing, omitted unavailable details, sensitive-value copy actions and empty/error states are present. | UXA-005, UXA-007, UXA-013. |
| Settings / unit / region / currency / advanced | Shared grouped rows, one flag implementation, persisted unit settings and truthful restricted disclosures are retained. | UXA-004, UXA-007; selector discoverability recommendation below. |
| Scan, launcher and destination picker | Explicit capture ownership, manual fallback, gallery cancellation, permission failure/retry and inactive-camera gating exist. | UXA-014; native permission/camera/back behavior needs device verification. |
| Shared feedback / overlays / navigation | Bounded toast queue, deduplication, result-owned feedback, button loading geometry and reduced-motion support are useful foundations. | UXA-015; UXA-001 requires actual semantic action tests, not merely labeled nodes. |

### Design Recommendations

These are not counted as reproduced defects. The author explicitly excluded
all three from this implementation; none was implemented or silently accepted.

1. **Selector discoverability:** Region and currency open long lists at the top
   without search or a selected-item jump (`country_selection_screen.dart:71`,
   `currency_selection_screen.dart:71`). Add search by name/code and make the
   saved choice easy to locate, while preserving current row/flag styling.
2. **Explicit scanner cancellation:** The destination picker offers manual entry
   and system back, but no clearly named Close action (`scan_screen.dart:283`).
   A small accessible close control would make cancel-without-changing-input
   distinct from switching entry mode. Do not clutter the persistent scan tab.
3. **Shared recovery layout:** Several feature failure bodies duplicate
   non-scrollable Center/Column arrangements, whereas Settings/bootstrap use
   scrollable recovery surfaces. Consolidate the invariant only after testing
   actual long safe messages at large text and keyboard-obstructed heights.
   Overflow was not reproduced for these bodies in this pass; this is targeted
   hardening, not a claim that every current failure screen overflows.

### Verification Gaps And Rejected Suspicions

- Fresh iOS and Android walkthroughs must cover the actual OS keyboard, edge
  back/predictive back, sheet dismissal, safe-area changes, platform permission
  dialogs, gallery/share sheets and camera capture. The 94 screenshots exclude
  platform views and must not be called full native end-to-end evidence.
- Run VoiceOver/TalkBack and keyboard/switch navigation across every enabled
  control after UXA-001/003 fixes. Host semantic trees prove structural defects,
  not how long a physical screen reader takes to speak each phrase/toast.
- Physical haptic feel, motion/frame pacing, GPU effects, memory under repeated
  navigation and lifecycle restarts were not measured in this audit. Existing
  source ownership patterns or unit tests are not substituted for profiling.
- Funded/unfunded real wallet flows, request regeneration across process restart
  and real payment settlement were not executed here. Existing SDK, fee-aware
  Max, swap backend, signing/disclosure, attribution and release constraints
  remain authoritative in the production tracker.
- The suspected hidden import-field focus after a manual carousel swipe did not
  reproduce: focus returned to the modal scope. Do not file it as a confirmed bug.
- The basic Receive amount sheet at 320x568 and 2x text produced no layout
  exception. This does not clear long numeric-value truncation in UXA-002.

### Fix Order And Sign-Off

1. Interaction safety: UXA-001, UXA-002, UXA-003, UXA-004, UXA-006.
2. Visual correctness: UXA-005, UXA-007, UXA-008, UXA-012, UXA-014.
3. Flow clarity and recovery: UXA-009, UXA-010, UXA-011, UXA-013, UXA-015.
4. The author excluded the three optional recommendations. Run the missing
   native and physical accessibility checks on a committed candidate; the fresh
   host captures below do not substitute for those checks.

No new spacing/radius ramp, font replacement, broad redesign or palette change
is justified by this audit. The missing reusable contracts are accessible action
ownership, exact amount-entry geometry, readable status foregrounds, stable
trailing values, payment-request lifecycle presentation, and accessible feedback
timing. Add narrowly scoped semantic roles only where these contracts require it.

### Implementation Closeout

- Implementation: `a487bbad812c3cb0c855766b3ff767c052d37eb0`. The full host tests and
  both builds ran on the source that became this commit; the pre-commit gate
  additionally checked the exact staged snapshot. This closeout only records
  evidence and immutable references; it does not change executable inputs.
- Scope: all **15** UXA code defects (3 P1, 12 P2) implemented and reviewed;
  **3** optional recommendations excluded. No new backend, SDK, palette,
  gradient recipe, shape policy or wallet operation was introduced.
- Production tracker reconciliation: **430 findings: 399 verified, 31 blocked**.
  File inventory: **576 files: 512 verified, 46 reviewed-clean, 18 blocked**;
  no unreviewed/fixing rows. These totals include historical work, not 576 fresh
  reviews in this implementation pass. The 35 changed files were re-reviewed.
- Verification: **907 passing tests**, including new semantic-action dispatch,
  exact amount geometry, recovery order, tab retention, hydration, contrast,
  expiry/resume, refresh/retry, hit-target and feedback-lifetime regressions.
  Coverage is **13,529 / 15,316 lines (88.33%)**; this is aggregate host coverage,
  not complete real-wallet or native-platform behavioral coverage.
- `make lint` covers code-generation consistency, formatting, fatal analysis,
  warning-free Dart documentation and repository policy validators. Final
  gate output: `/tmp/aster-ux-final-lint.log`; full tests:
  `/tmp/aster-ux-final-tests.log`.
- iOS Simulator Debug and Android Debug builds pass. Commands:
  `BUNDLE_FROZEN=true BUNDLE_PATH="$PWD/.bundle" bundle exec fvm flutter build ios --simulator --debug --no-pub`
  and `fvm flutter build apk --debug --no-pub`. CocoaPods remains necessary for
  the pinned SDK (SDK-002); legacy KGP warnings remain PLAT-002, not new app
  failures. Neither build is an application launch or signed release archive.
  Logs: `/tmp/aster-ux-final-ios-build.log` and
  `/tmp/aster-ux-final-android-build.log`.
- Toolchain: Flutter **3.47.0**, Dart **3.13.0**. No device was booted and no
  simulator, emulator or protected regtest data belonging to another task was
  touched. The SDK workspace is unchanged.
- **94 fresh host-engine captures** were generated in
  `build/ui-ux-fixes-2026-09-09/host/`, with six reviewed contact sheets in
  `build/ui-ux-fixes-2026-09-09/contact/`. These are deterministic test-fixture
  rasters, not new iOS OS captures or funded wallet evidence. The existing
  Desktop gallery is historical and was not replaced by this batch.
- Code review rejected two intermediate approaches: amount reflow moved the
  keypad during entry, and outlined Market glyphs degraded the authored style.
  Neither ships. Amounts instead have a stable-height, visibly scrollable
  viewport; Market uses existing dark/light foregrounds with readable capsules.

| IDs | Implemented contract | Verification |
| --- | --- | --- |
| UXA-001 | Enabled outer semantic actions share the guarded pointer path. Disabled/loading controls cannot activate. | Real semantic tap dispatch, pointer, Tab/Enter and guarded Home navigation tests. |
| UXA-002 | Exact numeric entry can scroll through every digit; changes reveal the fractional tail without moving the keypad. Receive content can scroll at large text. | Bundled DM Sans/Public Sans, BTC/sats/USDT extremes, 320px viewport at 1x/2x, full paragraph/scroll/geometry assertions. |
| UXA-003 | Numbered recovery words traverse 1 through 12 while retaining six-left/six-right placement. | Emitted semantic-node ordering and visual-column assertions. Physical speech remains ACCESS-019. |
| UXA-004 | Indexed screens keep stable wrappers and local state with offscreen input/semantics/tickers suppressed. | Repeated Settings scroll-state identity/offset retention and existing scanner lifecycle tests. |
| UXA-005 | Transaction values share a tight trailing slot. | Equal right-edge checks for short, long and hidden amounts at normal/large text. |
| UXA-006 | Immediate state hydration, explicit target resubscription and deterministic disposal keep the visible address consistent. | Valid regtest address validation, remount, target switch/back and controller text assertions. |
| UXA-007 | Readable statusForeground uses existing ink; accents and containers keep their colors. | All status foreground/container contrast ratios meet 4.5:1; copyWith/lerp and widget checks. |
| UXA-008 | Active Market tiles use opaque, appropriately polarized text/capsules; obsolete muted-text opacity is removed. | Rendered Send/Receive/Swap contrast guidelines at normal and 2x text, reviewed catalog; gradient recipes unchanged. |
| UXA-009 | Disabled Max explains missing fee-aware support or a fixed invoice amount locally. | Unlocked and fixed-invoice Send states; SEND-002 remains blocked. No fabricated max calculation. |
| UXA-010 | Receive names the selected asset/rail and actual localized expiry, if any. | Four-rail catalog and timed/address request assertions. |
| UXA-011 | Expiry removes QR and encoded text, keeps context and offers regeneration. | Exact deadline and inactive/resume clock tests; timers/subscriptions have one screen owner. |
| UXA-012 | Monetary option details measure/render numeric spans in Public Sans, leaving units and ordinary values in DM Sans. | Leaf-span font and compact reflow assertions. |
| UXA-013 | Details can refresh without losing current content, and show progress and refresh failure/retry. | Real ViewModel pending-to-failure-to-success sequence through the fake test engine; no production fake. |
| UXA-014 | The full manual-entry hit surface meets the existing 48px metric. | Edge tap plus Android/iOS target guidelines. |
| UXA-015 | Accessible messages remain until dismissal; keyboard focus pauses visual time; Escape and dismiss semantics work without stealing route focus. | Five assistive/focus/queue regressions plus long-message duration and existing foreground/background/reduced-motion checks. Physical speech timing remains ACCESS-019. |

**Remaining qualification:** TEST-019, ACCESS-019 and PERF-015 retain native
walkthrough, funded integration, physical assistive/haptic and measured
performance/leak requirements. All other deployment, authentication, Max,
attribution, SDK artifact and swap constraints in the production tracker remain.
These UI corrections do not establish signet or funds-bearing mainnet readiness.

## File Review

### Author Review Corrections

| ID | Status | Requested correction | Verification |
| --- | --- | --- | --- |
| VIS-022 | verified | Remove the CoinGecko credit from Home, including its screen-reader header labels; preserve real market data. | Home visible/semantic absence and signed price regressions pass; refreshed iOS Home inspected. Attribution placement/licensing remains the existing FIAT-002 release decision; no unrequested Settings UI was added. |
| VIS-023 | verified | Recovery copy must be a plain clickable icon and label, not a filled capsule. | Shared onboarding text action supports an icon and stable loading, blocks duplicate activation, preserves semantic labels and 48px targets; copy/security tests pass and refreshed iOS Create inspected. |
| VIS-024 | verified | Import fields must follow the description, with the remaining space before the safety message and Continue/Back. | Carousel/indicator belong to form content; only the footer belongs to bottom actions. Regression proves the 32px content gap and stable field position when viewport height grows; compact/large/keyboard and validation tests pass. Refreshed empty, final-page and keyboard-inset iOS captures inspected. |
| VIS-025 | verified | Market tiles must end with normal padding after their status capsule rather than leaving a large empty footer. | Removed the fixed minimum-height token and sized tiles to content. Geometry tests require exactly `spacing.lg` below the pill at normal and 2x text; refreshed iOS Market shell inspected. |

Provider attribution is a separate release requirement, not silently removed
from governance: [CoinGecko attribution guide](https://brand.coingecko.com/resources/attribution-guide).
These four changes are scoped to presentation; palette, fonts, repositories,
wallet operations and protected infrastructure are unchanged.

Linux golden follow-up: the shared outline/shadow/loader changes intentionally
change the presentation golden. The macOS and exact Linux rasters have been visually reviewed. The Linux
raster from run `34320894225` is adopted in `1b79465`; its golden check passes in
run `34322501973`. No tolerance increase or automatic baseline acceptance was used.

Inventory includes every non-generated Flutter UI/system source. Infrastructure
adapters and ViewModels are excluded from visual edits but their contracts remain
covered by existing tests. Each file is read, assessed against the reference, and
checked in its containing screen; an unchanged file can be reviewed-clean.

| File | Status | Evidence |
| --- | --- | --- |
| `lib/core/bootstrap/app_loader.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/features/home/presentation/screens/home_screen.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/asset_row.dart` | verified | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/assets_section.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/candle_chart.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/home_action_buttons.dart` | verified | Authored equal-width pills at normal scale; measured fit reflows accessible labels; native normal/2x captures reviewed. |
| `lib/features/home/presentation/widgets/home_header.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/mesh_gradient_background.dart` | verified | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/price_card.dart` | verified | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/market/presentation/screens/market_screen.dart` | reviewed-clean | Reviewed tile layout, squircles and unavailable actions; existing authored art retained. |
| `lib/features/market/presentation/widgets/market_tile.dart` | reviewed-clean | Reviewed tile layout, squircles and unavailable actions; existing authored art retained. |
| `lib/features/onboarding/presentation/screens/onboarding_create_wallet_screen.dart` | verified | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_import_wallet_screen.dart` | verified | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_shell.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_welcome_screen.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart` | verified | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart` | verified | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_status_panel.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_text_action.dart` | verified | VIS-023: plain icon/text copy, stable loading geometry, explicit accessible activation and disabled/loading tap prevention; focused and full suites pass. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_header.dart` | verified | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_icon_grid.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_mesh_background.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/receive/presentation/screens/receive_request_screen.dart` | verified | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/screens/receive_screen.dart` | reviewed-clean | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/widgets/receive_amount_sheet.dart` | verified | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/widgets/receive_request_qr.dart` | verified | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/scan/presentation/screens/scan_screen.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_background.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_camera.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_control_button.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_enter_address_button.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_frame.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_overlay_painter.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_wallet_header.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/send/presentation/screens/send_address_screen.dart` | verified | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/screens/send_amount_screen.dart` | verified | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/screens/send_screen.dart` | reviewed-clean | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/widgets/send_address_card.dart` | verified | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/widgets/send_card.dart` | verified | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/settings/presentation/screens/advanced_settings_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/bitcoin_unit_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/country_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/currency_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/network_configuration_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/settings_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/country_select_option_row.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/currency_select_option_row.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_choice_row.dart` | verified | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_links_card.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_status.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_version_footer.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/shell/presentation/screens/app_shell_screen.dart` | reviewed-clean | Reviewed shell lifecycle, tab ownership and compact floating nav. |
| `lib/features/shell/presentation/widgets/bottom_nav.dart` | reviewed-clean | Reviewed shell lifecycle, tab ownership and compact floating nav. |
| `lib/features/swap/presentation/screens/swap_screen.dart` | verified | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/asset_selector_sheet.dart` | verified | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/swap_card.dart` | verified | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/swap_pair.dart` | verified | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/transaction/presentation/screens/transaction_details_screen.dart` | reviewed-clean | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/screens/transaction_list_screen.dart` | verified | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/activity_balance_card.dart` | verified | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/transaction_detail_row.dart` | reviewed-clean | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/transaction_item.dart` | verified | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/wallet/presentation/pages/wallet_access_screen.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/pages/wallet_unavailable_screen.dart` | verified | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/payment_target_selection_view.dart` | verified | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/payment_target_tile.dart` | verified | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_asset_icon.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_lifecycle_gate.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/main.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/feedback/feedback_scope.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/feedback/toast_host.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/layout/window_insets.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/motion/motion_policy.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/routing/app_router.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/routing/navigation_command_scope.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/screens/animated_splash_screen.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/screens/splash_screen.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/app_theme.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/theme_context.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/art_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/color_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/component_metrics_tokens.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/effects_tokens.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/gradient_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/iconography_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/motion_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/radius_tokens.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/shadow_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/spacing_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/state_layer_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/stroke_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/type_role_tokens.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/tokens/typography_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/theme/typography.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/amount_text.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/app_skeletonizer.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_divider.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_icon_button.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_noise_texture.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_numeric_keypad.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_option_row.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_pill.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_selection_indicator.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_status_message.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/custom_app_bar.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/custom_button.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/custom_toast.dart` | verified | Transparent Material owns text defaults outside route Navigator; strict regression and four native variants pass. |
| `lib/shared/widgets/detail_row.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/grid_loader.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/squircle.dart` | verified | Read source; semantic type, palette, motion, shape and layout ownership checked. Reviewed in the containing UI/test scope; see native evidence limits below. |
| `lib/shared/widgets/aster_form_body.dart` | verified | Shared bottom action anchoring with scroll fallback for keyboard and large text. |
| `lib/shared/widgets/aster_split_card.dart` | verified | Single squircle boundary for content/footer; semantic padding and tonal treatment. |
| `lib/shared/widgets/aster_sheet_header.dart` | verified | Shared handle/title/close alignment and minimum target. |
| `lib/features/home/presentation/formatting/home_asset_display_formatter.dart` | verified | Exact compact fiat estimate plus full currency/availability semantics; no monetary arithmetic changed. |

## Evidence

### Final Boundary Review

The independent inventory cross-check also includes presentation barrels and
the camera lifecycle adapter. These were read, not just matched by a search.
The adapter owns no styling and preserves attachment/disposal behavior.

| File | Status | Evidence |
| --- | --- | --- |
| `lib/shared/layout/text_measurement.dart` | verified | Scoped paragraph measurement with locale/scaling and deterministic disposal; responsive regressions. |
| `lib/shared/layout/layout.dart` | reviewed-clean | Sorted boundary export, no internal/self barrel imports. |
| `lib/features/scan/data/services/scan_lifecycle_surface.dart` | reviewed-clean | Read lifecycle forwarding, observer removal and owner replacement. No visual styling to change; existing scan tests. |
| `lib/features/home/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/home/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/market/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/market/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/onboarding/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/onboarding/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/receive/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/receive/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/scan/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/scan/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/send/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/send/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/settings/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/settings/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/shell/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/shell/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/swap/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/swap/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/transaction/presentation/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/transaction/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/wallet/presentation/pages/pages.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/features/wallet/presentation/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/shared/screens/screens.dart` | reviewed-clean | Read exports; boundary policy. |
| `lib/shared/widgets/widgets.dart` | reviewed-clean | Read exports; boundary policy. |

### Run Log

#### Author Review Refinement

- VIS-022 through VIS-025 implement the four requested corrections. All 25
  visual findings are now verified; file coverage remains 143 sources with
  97 reviewed-clean and 46 verified. The original palette, fonts, SDK and
  wallet operation contracts are unchanged.
- Full local suite: **887/887 tests pass with coverage**, 3m04s at
  `--concurrency=2`. The 53 focused tests, fatal analysis, semantic design
  policy and whitespace checks also pass.
- Refreshed iOS-engine catalog: all four groups pass in 2m25s after a 17.1s
  build; 94 PNGs with 91 distinct rasters. Home, Create, Import empty/final
  carousel/keyboard-inset and Market shell inspected full-size. Apple Vision
  again decodes all four Receive QR payloads exactly.
- This is local/native presentation evidence for the refinement, not a new
  claim about remote CI or live wallet qualification. The gallery manifest
  records the resulting source commit. Previous candidate evidence follows.

#### Initial Restoration

- Code/QA candidate: `7798642b0913ac60e84d14c2596baaffef15e5d1`.
  Production styling is unchanged since `1b79465`; this follow-up strengthens
  fixture isolation, screenshot integrity and cross-host contrast measurement.
- Final image batch: 94 original iOS-engine Flutter-layer PNGs at 1260x2736,
  captured on `Aster-UI-Baseline-QA` / iPhone Air / iOS 26.5. Four catalog groups
  pass in 2m26s after a 10.4s build. All six contact sheets plus full-size shell
  screens were inspected. Apple Vision decodes all four Receive QR payloads
  exactly. The rejected identical-launch-image batch was not delivered.
- File review: 143 UI/system/boundary sources, 98 reviewed-clean and 45 verified.
  The architecture policy covers 315 Dart sources / 1042 imports / 239 exports;
  the semantic design policy checks all 121 UI implementation sources.
- All initial 21 visual findings are verified. This closes styling implementation and
  technical visual QA, not the author's final aesthetic approval or the app's
  separate funds-bearing release blockers.
- Exact platform CI run `34324442561` passes at `7798642`; Linux quality run
  `34324442536` passes its Test step, including the presentation golden and
  strict real-font/backdrop contrast cases.
- Strict pre-commit gates pass, including zero generated changes, fatal
  analysis, warning-free dartdoc for 315 public libraries, barrel/architecture/
  design/governance/configuration policy and the 574-file tracker inventory.
- The first aggregate rerun had one 8-second infrastructure subprocess timeout
  while native capture and code-generation gates ran concurrently. No product
  assertion failed. The unchanged complete suite then passes **883/883** with
  coverage at `--concurrency=2` in 3m02s. Its deadline was not relaxed.
  LCOV reports 13,354 / 15,159 instrumented lines (88.09%), SHA-256
  `a6356711f181fc1e4a38ce89c71e6f5bed16dd6986cffcb20255e1e3c7ef1544`.
- Normal `lib/main.dart` Simulator Debug build passes in 18.2s and launches
  successfully on the dedicated simulator; the actual native welcome view
  was inspected after replacing the catalog app. The SDK SwiftPM warning
  remains the pre-existing SDK-002 constraint, not a new styling regression.
- Gallery: `~/Desktop/Aster-Restored-UI-2026-09-09/Reviewed/index.html`.
  This evidence is test-fixture presentation, not live wallet, native camera,
  OS keyboard, physical haptic or funded payment qualification.

- `2f522c8` was committed and pushed as Zeus after format, generation,
  strict analysis, dartdoc, toolchain, architecture, design, barrel, governance,
  release-configuration and inventory gates passed.
- Previous local suite at `1b79465`: **879 tests pass with coverage**, 1m37s. An additional
  real-font onboarding rerun passes all 24 tests. Assertions were not relaxed.
- Earlier reviewed native catalog: **91 PNGs**, four groups pass, 10.4s iOS build and
  2m22s test run on the dedicated iPhone Air / iOS 26.5. Six contact sheets and
  full-size Home/reference compared. Empty/error/valid-page states are asserted.
- Apple Vision independently decodes all four Receive screenshots to exactly
  their test fixture strings, including the centered asset logos.
- Native raw protocol logging is disabled; it duplicated screenshot payloads
  into multi-gigabyte files. Only PNGs and a compact summary are retained.
- Linux run `34320894225` had three failures: the expected 0.88% golden drift
  (centered loader and unclipped toast shadow), and two wordmark contrast checks
  using Ahem. The exact Linux golden raster was downloaded, inspected and
  adopted; contrast tests now load the shipped DM Sans/Public Sans glyphs.
  VIS-014 then passes at `1b79465`; VIS-019's stricter backdrop measurement is
  verified locally and passes Linux run `34324442536`'s Test step at `7798642`.
- No palette, SDK dependency, wallet repository or monetary contract was
  changed. Physical haptic feel, native camera capture, live/funded payments,
  Android visual parity and native keyboard appearance are not certified by
  this styling catalog. Existing release constraints remain authoritative.

- V1: 59 focused Home, presentation-system, keypad, and exact-fiat-format tests
  pass. Strict analysis and semantic design-system policy pass. Compact controls
  now size to their content and retain that size while loading. Market headline
  rounding is presentation-only; exact monetary formatting remains the default.
- Strict analysis passes after V1-V3 edits.
- Onboarding: 23 tests pass, including contrast, 320x568 at 2x text, 430x932,
  lowercase/word validation, carousel focus, and submission ownership.
- The catalog uses test-only engines, market responses and public mnemonic
  vectors. It does not touch the SDK, native wallets or another task's stack.
- This catalog certifies visual presentation, not native-wallet runtime behavior.
- V1-V3 regression suite: 229 tests pass, including the reviewed macOS golden,
  exact fiat formatting, Send/Receive, settings, activity, shared controls and
  navigation. Host catalog: all four groups pass.
- First iOS simulator catalog run: four groups pass in 2m14s after a 24.8s build
  on Aster-UI-Baseline-QA (iOS 26.5). Screenshot export is being rerun through the
  host driver because Flutter removes its temporary test container afterward.
