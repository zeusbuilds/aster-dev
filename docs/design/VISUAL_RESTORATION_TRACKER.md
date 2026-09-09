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

| Phase | Scope | Status | Verification / commit |
| --- | --- | --- | --- |
| V1 | Shared geometry, controls, Home, shell | fixing | Implementation and 59 focused tests pass; final iOS visual check remains V4 |
| V2 | Send, Receive, Swap, selection, sheets | fixing | Restyled; focused regression suite and screenshots in progress |
| V3 | Onboarding, wallet access, settings, activity, scanner, market | fixing | Source review complete; 23 onboarding checks pass |
| V4 | Independent visual audit, responsive tests, iOS screenshots of all screens and states | fixing | Shared host/native catalog implemented; screenshot review underway |

## Findings

| ID | Status | Evidence and required correction | Verification |
| --- | --- | --- | --- |
| VIS-001 | fixing | Home asset rows split content into competing equal-width columns and repeat available balance. Restore the original name/unit and total/fiat hierarchy while preserving availability in activity details and accessibility. | Pending |
| VIS-002 | fixing | Home price/header horizontal insets differ, chart/error states change hero composition, and floating nav is wider than the reference. Align Home geometry to the approved reference with responsive expansion. | Pending |
| VIS-003 | fixing | Destination/amount cards use independent top/bottom shapes with differing outlines; Paste and Max have drifted into primary action styling. Restore one coherent card boundary and contextual compact controls. | Pending |
| VIS-004 | fixing | Current Receive request uses a different QR/action composition. Restore the QR card and grouped action rows, retaining truthful request expiry and generation states. | Pending |
| VIS-005 | fixing | New screens need the same outlined groups, alignment, insets, type hierarchy, and responsive behavior as the original components. Review every row below. | Pending |
| VIS-006 | fixing | Screenshots must cover every route, four-rail payment variants, sheets, loading/error/empty states, keyboard behavior, and compact/large layouts. Label fixtures and unsupported states honestly. | Pending |

| VIS-007 | fixing | Compact pills expanded under loose constraints and changed width while loading. Preserve content sizing and stable loading geometry; make the full 48px hit target interactive without duplicate haptics. | Added geometry, edge-tap, loading and haptic regression checks. |
| VIS-008 | fixing | Split-card children could overpaint outlines, while clipping could cut shadows. Shared Squircle now paints background/shadows outside child clipping and the outline in the foreground. | Foreground shape/theme test; rendered catalog review. |
| VIS-009 | fixing | Settings chevrons and DetailRow values drifted inward for short values; inset dividers were asymmetric. Reserve a stable trailing column and equal divider insets. | Shared trailing-edge regression. |
| VIS-010 | fixing | Recovery wordmark was reduced to label size; generated words could truncate with large type. Restore semantic 40px wordmark, recovery field shape, untruncated words and bottom-anchored import. | 23 onboarding tests pass. |
| VIS-011 | fixing | Small recovery text over the brightest glass/mesh failed contrast. Use a semantic glass-content scrim from existing palette and opaque number labels. | Automated contrast checks pass at phone and compact scaled sizes. |
| VIS-012 | fixing | Send amount entered in sats was labeled BTC. Display the formatter's denomination, keeping asset identity distinct. | Four-rail amount screenshots and payment tests. |
| VIS-013 | fixing | Wallet-unavailable container swallowed Retry semantics; route error used an inconsistent, non-scrolling layout. Keep explicit child semantics, shared app bar and scrollable safe-area recovery. | Shared/widget suite and catalog. |

## File Review

Linux golden follow-up: the shared outline/shadow/loader changes intentionally
change the presentation golden. The macOS raster has been regenerated and
visually reviewed; the exact Linux raster must be retrieved from CI and reviewed
before accepting its replacement. This is VIS-014 (fixing), not a tolerated
pixel difference or an auto-approved baseline.

Inventory includes every non-generated Flutter UI/system source. Infrastructure
adapters and ViewModels are excluded from visual edits but their contracts remain
covered by existing tests. Each file is read, assessed against the reference, and
checked in its containing screen; an unchanged file can be reviewed-clean.

| File | Status | Evidence |
| --- | --- | --- |
| `lib/core/bootstrap/app_loader.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/features/home/presentation/screens/home_screen.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/asset_row.dart` | fixing | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/assets_section.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/candle_chart.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/home_action_buttons.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/home_header.dart` | reviewed-clean | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/mesh_gradient_background.dart` | fixing | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/home/presentation/widgets/price_card.dart` | fixing | Compared approved hero, two-line rows, pill actions, quote/visibility states; source review complete. |
| `lib/features/market/presentation/screens/market_screen.dart` | reviewed-clean | Reviewed tile layout, squircles and unavailable actions; existing authored art retained. |
| `lib/features/market/presentation/widgets/market_tile.dart` | reviewed-clean | Reviewed tile layout, squircles and unavailable actions; existing authored art retained. |
| `lib/features/onboarding/presentation/screens/onboarding_create_wallet_screen.dart` | fixing | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_import_wallet_screen.dart` | fixing | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_shell.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/screens/onboarding_welcome_screen.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart` | fixing | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_import_wallet_word_page.dart` | fixing | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_status_panel.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_text_action.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_header.dart` | fixing | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_icon_grid.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/onboarding/presentation/widgets/onboarding_welcome_mesh_background.dart` | reviewed-clean | Compared wordmark, mesh, field curves and anchoring; 23 onboarding tests pass, including compact text and contrast. |
| `lib/features/receive/presentation/screens/receive_request_screen.dart` | fixing | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/screens/receive_screen.dart` | reviewed-clean | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/widgets/receive_amount_sheet.dart` | fixing | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/receive/presentation/widgets/receive_request_qr.dart` | fixing | Reviewed QR/request/amount sheet and expiry/generation states; centered asset QR and shared sheet header. |
| `lib/features/scan/presentation/screens/scan_screen.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_background.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_camera.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_control_button.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_enter_address_button.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_frame.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_overlay_painter.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/scan/presentation/widgets/scan_wallet_header.dart` | reviewed-clean | Read every scan widget and painter; existing frame/overlay/control style retained, camera fixture clearly isolated. |
| `lib/features/send/presentation/screens/send_address_screen.dart` | fixing | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/screens/send_amount_screen.dart` | fixing | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/screens/send_screen.dart` | reviewed-clean | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/widgets/send_address_card.dart` | fixing | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/send/presentation/widgets/send_card.dart` | fixing | Reviewed address/amount/selection and operation gating; restored split cards and inset keypad. |
| `lib/features/settings/presentation/screens/advanced_settings_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/bitcoin_unit_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/country_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/currency_selection_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/network_configuration_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/screens/settings_screen.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/country_select_option_row.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/currency_select_option_row.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_choice_row.dart` | fixing | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_links_card.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_status.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/settings/presentation/widgets/settings_version_footer.dart` | reviewed-clean | Reviewed all rows, selectors and unavailable disclosures; consistent trailing edges, insets, numeric examples. |
| `lib/features/shell/presentation/screens/app_shell_screen.dart` | reviewed-clean | Reviewed shell lifecycle, tab ownership and compact floating nav. |
| `lib/features/shell/presentation/widgets/bottom_nav.dart` | reviewed-clean | Reviewed shell lifecycle, tab ownership and compact floating nav. |
| `lib/features/swap/presentation/screens/swap_screen.dart` | fixing | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/asset_selector_sheet.dart` | fixing | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/swap_card.dart` | fixing | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/swap/presentation/widgets/swap_pair.dart` | fixing | Reviewed pair composition and sheet; two-tone card restored without pretending unavailable swaps execute. |
| `lib/features/transaction/presentation/screens/transaction_details_screen.dart` | reviewed-clean | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/screens/transaction_list_screen.dart` | fixing | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/activity_balance_card.dart` | fixing | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/transaction_detail_row.dart` | reviewed-clean | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/transaction/presentation/widgets/transaction_item.dart` | fixing | Reviewed combined feed, balance, detail rows and metadata; restored unframed activity rows. |
| `lib/features/wallet/presentation/pages/wallet_access_screen.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/pages/wallet_selection_screen.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/pages/wallet_unavailable_screen.dart` | fixing | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/payment_target_selection_view.dart` | fixing | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/payment_target_tile.dart` | fixing | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_asset_icon.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_lifecycle_gate.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/features/wallet/presentation/widgets/wallet_select_option_row.dart` | reviewed-clean | Reviewed lifecycle/access/selection and four payment targets; shared groups and accessible retry maintained. |
| `lib/main.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/feedback/feedback_scope.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/feedback/toast_host.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/layout/window_insets.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/motion/motion_policy.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/routing/app_router.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/routing/navigation_command_scope.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/screens/animated_splash_screen.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/screens/splash_screen.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/app_theme.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/theme_context.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/art_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/color_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/component_metrics_tokens.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/effects_tokens.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/gradient_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/iconography_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/motion_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/radius_tokens.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/shadow_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/spacing_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/state_layer_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/stroke_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/type_role_tokens.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/tokens/typography_tokens.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/theme/typography.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/amount_text.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/app_skeletonizer.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_divider.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_icon_button.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_noise_texture.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_numeric_keypad.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_option_row.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_pill.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_selection_indicator.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/aster_status_message.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/custom_app_bar.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/custom_button.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/custom_toast.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/detail_row.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/grid_loader.dart` | reviewed-clean | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |
| `lib/shared/widgets/squircle.dart` | fixing | Read source; semantic type, palette, motion, shape and layout ownership checked. Native screenshot check pending. |

| `lib/shared/widgets/aster_form_body.dart` | fixing | Shared bottom action anchoring with scroll fallback for keyboard and large text. |
| `lib/shared/widgets/aster_split_card.dart` | fixing | Single squircle boundary for content/footer; semantic padding and tonal treatment. |
| `lib/shared/widgets/aster_sheet_header.dart` | fixing | Shared handle/title/close alignment and minimum target. |
| `lib/features/home/presentation/formatting/home_asset_display_formatter.dart` | fixing | Exact compact fiat estimate plus full currency/availability semantics; no monetary arithmetic changed. |

## Evidence

- V1: 59 focused Home, presentation-system, keypad, and exact-fiat-format tests
  pass. Strict analysis and semantic design-system policy pass. Compact controls
  now size to their content and retain that size while loading. Market headline
  rounding is presentation-only; exact monetary formatting remains the default.
- Strict analysis passes after V1-V3 edits.
- Onboarding: 23 tests pass, including contrast, 320x568 at 2x text, 430x932,
  lowercase/word validation, carousel focus, and submission ownership.
- The catalog uses test-only engines, market responses and public mnemonic
  vectors. It does not touch the SDK, native wallets or another task's stack.
- No final visual completion or native runtime verification is claimed yet.
- V1-V3 regression suite: 229 tests pass, including the reviewed macOS golden,
  exact fiat formatting, Send/Receive, settings, activity, shared controls and
  navigation. Host catalog: all four groups pass.
- First iOS simulator catalog run: four groups pass in 2m14s after a 24.8s build
  on Aster-UI-Baseline-QA (iOS 26.5). Screenshot export is being rerun through the
  host driver because Flutter removes its temporary test container afterward.
