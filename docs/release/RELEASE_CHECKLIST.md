# Release Candidate Checklist

A release candidate is the exact commit that passes every applicable item. Run
from a clean worktree and record commands/results in the production tracker.

## Host

- [ ] repository-local Zeus identity is configured; global identity unchanged
- [ ] `git status --short` is clean
- [ ] immutable SDK `resolved-ref` matches the approved commit
- [ ] `fvm flutter --version` matches `.fvmrc`
- [ ] `make lint`
- [ ] `fvm flutter test --coverage`
- [ ] dependency, license, discontinued-package, and advisory review

## Platforms

- [ ] clean iOS build and XCTest
- [ ] iOS install/launch smoke on the recorded simulator/device
- [ ] clean Android release APK/AAB build and native tests
- [ ] Android install/launch smoke on the recorded ABI/API
- [ ] package IDs, entitlements, backup policy, signing, and release metadata
- [ ] artifact sizes and SHA-256 digests recorded

## Product And Security

- [ ] create/import and process-restart proof
- [ ] all configured payment rails: validate, receive, send, failure, retry
- [ ] activity normalization and details
- [ ] screen-reader traversal, text scaling, contrast, keyboard, touch targets
- [ ] physical haptics, camera/gallery, background capture policy
- [ ] profile launch, frame, memory growth, leaks, and native-handle cleanup
- [ ] no secret-bearing logs/screenshots/fixtures

## Closeout

- [ ] every repository-owned non-generated file independently reviewed
- [ ] zero unreviewed tracker rows
- [ ] zero untracked findings
- [ ] blockers and accepted constraints listed in release notes
- [ ] exact commit pushed to the authorized remote
- [ ] eligibility stated separately for internal beta, signet, and mainnet

Internal beta eligibility does not imply funds-bearing mainnet eligibility.
