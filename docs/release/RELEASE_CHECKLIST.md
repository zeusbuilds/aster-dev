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
- [ ] root iOS privacy manifest is present in the built app and its approved
      required-reason entries match the exact executable/API scan
- [ ] iOS install/launch smoke on the recorded simulator/device
- [ ] clean Android release AAB or `make android-release-apks` build and native tests
- [ ] direct APK artifacts contain exactly one ABI; never distribute the
      universal `app-release.apk`
- [ ] Android install/launch smoke on the recorded ABI/API
- [ ] package IDs, entitlements, backup policy, signing, and release metadata
- [ ] public app version/build number and upgrade policy are approved
- [ ] Android APK/AAB artifacts are unsigned candidates or match the approved
      `UTEXO_RELEASE_CERT_SHA256`; debug-signed artifacts are rejected
- [ ] AAB requests `PAGE_ALIGNMENT_16K`, every 64-bit native library has 16 KiB
      ELF LOAD alignment, split APK ZIP alignment passes, and a 16 KiB runtime
      smoke passes without compatibility mode
- [ ] approved `UTEXO_MARKET_API_BASE_URL`, provider license/attribution, proxy
      availability, and server-side credential ownership
- [ ] artifact sizes and SHA-256 digests recorded

## Product And Security

- [ ] create/import and process-restart proof
- [ ] all configured payment rails: validate, receive, send, failure, retry
- [ ] activity normalization and details
- [ ] screen-reader traversal, text scaling, contrast, keyboard, touch targets
- [ ] physical haptics, camera/gallery, background capture policy
- [ ] profile launch, frame, memory growth, leaks, and native-handle cleanup
- [ ] performance samples were taken on an idle host and repeated for stability
- [ ] no secret-bearing logs/screenshots/fixtures
- [ ] App Store privacy, Play Data safety, privacy policy, and encryption/export
      declarations are approved against the exact deployment data-flow map

## Closeout

- [ ] every repository-owned non-generated file independently reviewed
- [ ] zero unreviewed tracker rows
- [ ] zero untracked findings
- [ ] blockers and accepted constraints listed in release notes
- [ ] exact commit pushed to the authorized remote
- [ ] eligibility stated separately for internal beta, signet, and mainnet

Internal beta eligibility does not imply funds-bearing mainnet eligibility.
