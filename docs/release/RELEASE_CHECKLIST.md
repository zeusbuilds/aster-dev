# Release Candidate Checklist

A release candidate is the exact commit that passes every applicable item. Run
from a clean worktree and record commands/results in the production tracker.

## Host

- [ ] repository-local Zeus identity is configured; global identity unchanged
- [ ] `git status --short` is clean
- [ ] immutable SDK `resolved-ref` matches the approved commit
- [ ] selected wallet backend matches the approved native store format. Record
      the SDK revision, both native artifact hashes, and the running library
      version and source revision on iOS and Android
- [ ] `fvm flutter --version` matches `.fvmrc`
- [ ] Gradle wrapper distribution checksum matches the reviewed official digest
- [ ] Gradle dependency verification passes without trust exceptions and covers
      Debug, Profile, Release, bundle, and native-test graphs
- [ ] Bundler 4.0.10 resolves the checksummed `Gemfile.lock`, and every owned
      iOS Flutter/CocoaPods command uses CocoaPods 1.16.2 through `bundle exec`
- [ ] `make lint`
- [ ] `fvm flutter test --coverage`
- [ ] dependency, license, discontinued-package, and advisory review
- [ ] one sorted non-secret release manifest passes
      `make verify-release-configuration` for the intended audience; its
      SHA-256 is recorded and the file remains uncommitted
- [ ] GitHub Quality and Platform compile workflows pass on this exact commit;
      compile CI is not recorded as runtime or signing evidence

## Platforms

- [ ] `make ios-native-test IOS_SIMULATOR_ID=<id>` and
      `make ios-storage-test IOS_SIMULATOR_ID=<id>`
- [ ] root iOS privacy manifest is present in the built app and its approved
      required-reason entries match the exact executable/API scan
- [ ] iOS install/launch smoke on the recorded simulator/device
- [ ] unsigned iOS archive built through `make ios-release-archive`, or signed
      IPA built through `make ios-release-ipa` with an ignored approved export
      policy; the distributed IPA passes archive preflight plus extracted
      identity/privacy/signature/provisioning/size checks and exact digests are
      recorded
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
- [ ] mainnet indexer, RGB proxy protocol, and EVM chain match the approved
      deployment. For RGB_L1 qualify proxy 1.0 and the issuer-approved CON V1
      USDT contract ID, schema, precision, and BFA backing before accepting
      deposits
- [ ] public app version/build number and upgrade policy are approved
- [ ] Android APK/AAB artifacts are unsigned candidates or match the approved
      `ASTER_RELEASE_CERT_SHA256`; debug-signed artifacts are rejected
- [ ] every signed AAB payload entry verifies under one approved certificate;
      partially signed, modified, duplicate-entry, and multi-signer bundles fail
- [ ] APK/AAB archive inspection rejects unsafe/duplicate names and resource
      over-expansion, proves the exact ABI/required-library matrix, and extracts
      native libraries only through the owned structured ZIP boundary
- [ ] every repository-owned shell entrypoint uses the pinned bounded-command
      adapter for all external work; quick, inspection, and build/platform
      profiles retain independent output ceilings, strict decoding, deadlines,
      first-failure cleanup, and complete descendant termination
- [ ] every directly distributed APK verifies with Signature Scheme v2 or v3;
      v1/JAR-only signatures are rejected
- [ ] AAB requests `PAGE_ALIGNMENT_16K`, every 64-bit native library has 16 KiB
      power-of-two and offset/address-congruent ELF LOAD alignment, split APK
      ZIP alignment passes, and a 16 KiB runtime smoke passes without
      compatibility mode
- [ ] approved `ASTER_MARKET_API_BASE_URL`, provider license/attribution, proxy
      availability, and server-side credential ownership
- [ ] artifact sizes and SHA-256 digests recorded
- [ ] AAB, split APK, archived iOS app, and IPA remain within reviewed
      regression budgets; no budget was raised merely to pass the candidate

## Product And Security

- [ ] create/import and process-restart proof
- [ ] all configured payment rails: validate, receive, send, failure, retry
- [ ] funded BTC and RGB sends retain their exact identity through process
      interruption, lost responses, and wallet reopen on both platforms.
      Qualification verifies that retries cannot create a second transaction
      and that an unresolved payment retains its mutation fence
- [ ] backup and restore recover the same wallet's keys, RGB ownership, and
      durable payment records as one consistent state. Run restored-wallet
      qualification with a completed send and with an interrupted send
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
- [ ] CODEOWNERS, dependency-update policy, and required branch protections are
      confirmed; source policy does not substitute for remote administrator state
- [ ] blockers and accepted constraints listed in release notes
- [ ] exact commit pushed to the authorized remote
- [ ] eligibility stated separately for internal beta, signet, and mainnet

Internal beta eligibility does not imply funds-bearing mainnet eligibility.
