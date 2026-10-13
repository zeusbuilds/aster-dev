# Resume Aster and RGB SDK Work

Use the block below as the first message in a restored or new Codex task. Change
the workspace root if the new macOS account has a different home directory.
This file is context, not permission to reset wallets, move funds, publish, or
mutate another task's environment.

```text
We are resuming Aster and rgb_sdk_flutter after a system reset.

Read these files before changing code:
1. docs/handoff/SYSTEM_CONTEXT.md
2. docs/handoff/RESET_AND_RESTORE.md
3. docs/handoff/OPEN_ISSUES_SNAPSHOT.md
4. docs/handoff/WORKSPACE_SNAPSHOT.json
5. docs/PRODUCTION_REFACTOR_TRACKER.md
6. ../rgb-sdk-flutter/doc/RELEASE_READINESS_TRACKER.md
7. ../rgb-sdk-flutter/doc/API_COMPATIBILITY_AND_DIVERGENCE.md
8. ../rgb-sdk-flutter/doc/WEBRGB_AND_BURNS.md

Original workspace root: /Users/hardik/Projects.
App: aster-dev. SDK: rgb-sdk-flutter.
App working origin: private github.com/zeusbuilds/aster-dev.
SDK working origin: private github.com/zeusbuilds/rgb-sdk-flutter.
SDK public mirror: github.com/UTEXO-Protocol/flutter-sdk.
Use Zeus project-scoped authentication and repository-local commit identity
zeusbuilds <zeusbuilds113@gmail.com>. Do not change the global GitHub account,
global Git identity, origin URLs, repository visibility, or existing history.

Last implementation baseline:
- SDK: 7c44506fdfe1dae6f3a6fe884f849c7ca2ad028b.
- App implementation: 1a7ca658a0267ae601e975ed3204e5d7426568e7.
- App documentation closeout before this handoff:
  1ccbd74f26c2572f168e12e3bf9e8533a3c6eb4a.
- The handoff itself is a later documentation change. Inspect HEAD and remote
  ancestry; do not reset to an older commit just to match these hashes.
- RN dev comparison: e38329eba11cce16e3bea75b8a4e7becd52c0036 / beta.37.
- RLN: 0.16.0-beta.3 / 8777d71d7781b408fcce89c9c965ae29e8ad2300.

Aster is the product; UTEXO is the protocol integration. Keep Riverpod MVVM,
one serialized WalletRuntime, stable public SDK APIs, exact integer money,
typed failures, and no fake production behavior. Preserve the user's current
UI, colors, DM Sans text, Public Sans numeric spans, squircles and pill controls.
Lightning is outside the current app release. Swap has no execution backend.
PKG-006 permits development/internal beta, not funds-bearing mainnet readiness.

First perform a read-only restoration preflight. Check repository status and
pins, toolchains, available disk, recovered local files and credentials by
presence only, device ownership, and bounded stack health. Do not print secrets.
Do not assume a clone recovered ignored files, keychain state, Docker volumes,
RGB state, pending burn journals, test fixtures or other tasks' uncommitted work.

Protect Iris/WDK and rgb-lightning-node-perf-lab resources. Use only Aster's
separate stack and Aster-owned devices when working on this app. Never run
another project's reset script or reuse its test asset because its ticker is USDT.

The handoff identifies additional truth-reconciliation work: external-signer
burn now exists in the pinned native source, while RN/Flutter facade capability
remains restricted; old docs must not call that a native impossibility. The
Iris bridge's backend mint/burn test passed locally, but that is not Flutter
runtime evidence or a completed Iris WalletConnect frontend flow.

Report what was restored, what is absent or changed, and the next executable
work group before implementing. Then continue the user-selected work with
tracker updates, focused tests, strict analysis, review, and exact evidence.
Never promote historical, source-equivalent, mocked, compile-only or another
SDK's test results into current installed-device/funded qualification.
```

Original task: **Package & App**,
`019e4624-fd92-7a41-b98b-3790c02da3e1`. Restoring the old task is useful but is
not required to continue engineering work from this handoff.
