# Release Candidate Checklist

A release candidate is the exact commit that passes every applicable item. Run
from a clean worktree and record commands/results in the production tracker.

## Host

- [ ] repository-local Zeus identity is configured; global identity unchanged
- [ ] `git status --short` is clean
- [ ] immutable SDK `resolved-ref` matches the approved commit
- [ ] `fvm flutter --version` matches `.fvmrc`
- [ ] Gradle wrapper distribution checksum matches the reviewed official digest
- [ ] Gradle dependency verification passes without trust exceptions and covers
      Debug, Profile, Release, bundle, and native-test graphs
- [ ] Bundler 4.0.10 resolves the checksummed `Gemfile.lock`, and every owned
      iOS Flutter/CocoaPods command uses CocoaPods 1.16.2 through `bundle exec`
- [ ] `make lint`
- [ ] `fvm flutter test --coverage`
- [ ] dependency, license, discontinued-package, and advisory review

## Platforms

- [ ] `make ios-native-test IOS_SIMULATOR_ID=<id>` and
      `make ios-storage-test IOS_SIMULATOR_ID=<id>`
- [ ] root iOS privacy manifest is present in the built app and its approved
      required-reason entries match the exact executable/API scan
- [ ] iOS install/launch smoke on the recorded simulator/device
- [ ] clean `make android-release-bundle` or `make android-release-apks` run;
      guarded preparation reports unchanged lock/graph and no dev plugins
- [ ] APK/AAB application ID and version name match committed source; AAB uses
      the base build number and each split APK uses Flutter's verified ABI code
- [ ] direct APK artifacts contain exactly one ABI; never distribute the
      universal `app-release.apk`
- [ ] `make android-native-test` and
      `make android-storage-test ANDROID_DEVICE_ID=<id>`
- [ ] Android install/launch smoke on the recorded ABI/API
- [ ] package IDs, entitlements, backup policy, signing, and release metadata
- [ ] Apple export-compliance classification is approved by the release owner;
      submission metadata and `ITSAppUsesNonExemptEncryption`, if applicable,
      match that documented legal classification
- [ ] every Release wallet service endpoint is TLS-protected; no HTTP, `tcp`,
      or `rpc` loopback development transport survives composition
- [ ] public app version/build number and upgrade policy are approved
- [ ] Android APK/AAB artifacts are unsigned candidates or match the approved
      `UTEXO_RELEASE_CERT_SHA256`; debug-signed artifacts are rejected
- [ ] every signed AAB payload entry verifies under one approved certificate;
      partially signed, modified, duplicate-entry, and multi-signer bundles fail
- [ ] APK/AAB archive inspection rejects unsafe/duplicate names and resource
      over-expansion, proves the exact ABI/required-library matrix, and extracts
      native libraries only through the owned structured ZIP boundary
- [ ] every directly invoked Android identity inspector uses the owned streamed
      process boundary with independent output ceilings, strict decoding, a
      deadline, and forced child termination
- [ ] every directly distributed APK verifies with Signature Scheme v2 or v3;
      v1/JAR-only signatures are rejected
- [ ] AAB requests `PAGE_ALIGNMENT_16K`, every 64-bit native library has 16 KiB
      power-of-two and offset/address-congruent ELF LOAD alignment, split APK
      ZIP alignment passes, and a 16 KiB runtime smoke passes without
      compatibility mode
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
