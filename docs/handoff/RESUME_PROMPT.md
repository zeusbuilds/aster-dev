# Resume Aster and RGB SDK Work

Use the block below as the first message in a restored or new Codex task.
Repositories may be cloned anywhere; identify them by Git remote and revision,
not their old folder names or assumed sibling layout.
This file is context, not permission to reset wallets, move funds, publish, or
mutate another task's environment.

```text
We are resuming Aster and rgb_sdk_flutter after a system reset.

First locate/map the repositories by remote, not by an old absolute path:
- ASTER_ROOT: https://github.com/zeusbuilds/aster-dev.git (private).
- SDK_ROOT: https://github.com/zeusbuilds/rgb-sdk-flutter.git (private).
- SDK public mirror: https://github.com/UTEXO-Protocol/flutter-sdk.git.
The roots may be unrelated directories. Confirm existing roots with
git rev-parse --show-toplevel and git remote get-url origin; do not rename or
move checkouts to match this handoff. Ask for the new locations if unknown.

Read these repository-relative files before changing code:
In Aster: docs/handoff/SYSTEM_CONTEXT.md, docs/handoff/RESET_AND_RESTORE.md,
docs/handoff/OPEN_ISSUES_SNAPSHOT.md, docs/handoff/WORKSPACE_SNAPSHOT.json,
and docs/PRODUCTION_REFACTOR_TRACKER.md.
In the SDK: doc/RELEASE_READINESS_TRACKER.md,
doc/API_COMPATIBILITY_AND_DIVERGENCE.md and doc/WEBRGB_AND_BURNS.md.
The SDK baseline files are also available under
https://github.com/UTEXO-Protocol/flutter-sdk/tree/7c44506fdfe1dae6f3a6fe884f849c7ca2ad028b/doc
Use Git references for source; restore ignored state only from an explicit
backup mapping. Snapshot checkout keys and old device IDs are historical.
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
- RN comparison: https://github.com/UTEXO-Protocol/rgb-sdk-rn.git,
  dev at e38329eba11cce16e3bea75b8a4e7becd52c0036 / beta.37.
- RLN: https://github.com/UTEXO-Protocol/rgb-lightning-node.git,
  v0.16.0-beta.3 at 8777d71d7781b408fcce89c9c965ae29e8ad2300.

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
