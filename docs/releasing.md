# Releasing Broccoli

Broccoli uses one immutable, notarized Apple-silicon ZIP for direct downloads, Sparkle, and Homebrew. Sparkle 2.9.6 is pinned in `Package.resolved`. The application requires signed appcasts and verifies updates before extraction; system profiling is disabled.

## Release identities

- Production bundle ID: `dev.gauravpandey.broccoli`
- Local update-test bundle ID: `dev.gauravpandey.broccoli.updatetest`
- Minimum system: macOS 26
- Production architecture: arm64 only
- Production feed: `https://yednapg.github.io/broccoli/appcast.xml`

Do not change the production bundle identifier, Developer ID identity, or designated requirement between releases. macOS uses that identity when deciding whether Accessibility and Automation grants still belong to the application.

## Local update rehearsal

Resolve the exact Sparkle dependency, then run the end-to-end harness:

```sh
swift package resolve
zsh scripts/test-local-update.sh
```

The harness creates a temporary keychain and EdDSA key, builds `0.0.1 (1)` and `0.0.2 (2)`, signs a feed and release notes, serves them only on `127.0.0.1`, installs the baseline in a temporary Applications directory, drives Sparkle through replacement and relaunch, verifies build 2, and restores the prior keychain configuration. Its trap removes the temporary app, key, feed, cask, server, and update-test defaults even after a failure.

To include a local Homebrew installation in the same update path:

```sh
BROCCOLI_TEST_HOMEBREW=1 zsh scripts/test-local-update.sh
```

Zap is intentionally blocked unless the test is running in a disposable account or VM:

```sh
BROCCOLI_TEST_HOMEBREW=1 \
BROCCOLI_TEST_HOMEBREW_ZAP=1 \
BROCCOLI_DISPOSABLE_ACCOUNT=YES \
zsh scripts/test-local-update.sh
```

For a single local artifact rehearsal, use the release interface directly. The output directory must be empty:

```sh
zsh scripts/release.sh \
  --mode rehearse \
  --version 0.0.2 \
  --build 2 \
  --channel stable \
  --priority routine \
  --notes docs/release-notes/0.0.2.md \
  --output /tmp/broccoli-0.0.2
```

`rehearse` cannot create a tag, GitHub release, Pages deployment, tap commit, or push. It produces the ZIP, signed release notes and appcast, manifest, and exact-checksum cask locally.

## Channels and update policy

The appcast uses the default Sparkle channel for stable releases and `beta` for beta releases. Beta clients accept both; stable clients accept only the default channel. `CFBundleVersion` must increase globally across both channels. Returning from beta never downgrades an installation: Sparkle waits for a stable item whose build number is higher than the installed beta.

The custom `<broccoli:priority>` value is `routine`, `important`, or `critical`. A critical entry must also have Sparkle's `<sparkle:criticalUpdate>` marker or Broccoli rejects it as a malformed feed item.

- Stable routine releases use 86,400-second Sparkle rollout phases (seven groups).
- Stable important releases use 21,600-second phases.
- Critical and beta releases are immediate.
- No priority forces installation or relaunch. Automatic important/critical downloads require the user's prior opt-in and a destination Broccoli can replace without an unexpected authorization prompt.

## Required release gates

Production remains blocked until all of these are true:

- Apple Developer enrollment is active and a Developer ID Application certificate is installed.
- The Sparkle private key has two verified, encrypted offline backups.
- A private notarization submission has succeeded, been stapled, quarantined, installed, and updated as both admin and standard users.
- The clean-install/update matrix passes on arm64 macOS 26 and 27.
- Accessibility and Automation grants survive Sparkle and Homebrew upgrades.
- GitHub CLI authentication is valid.

The GitHub `production` environment must require manual approval and define each workflow gate variable as `true`: `APPLE_DEVELOPER_READY`, `SPARKLE_BACKUPS_VERIFIED`, `NOTARIZATION_REHEARSAL_PASSED`, `MACOS26_MATRIX_PASSED`, and `MACOS27_MATRIX_PASSED`.

## Production secrets

Configure the protected `production` environment with:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `DEVELOPER_ID_APPLICATION_IDENTITY`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APP_SPECIFIC_PASSWORD`
- `SPARKLE_EDDSA_PRIVATE_KEY` and `SPARKLE_EDDSA_PUBLIC_KEY`
- `TAP_GITHUB_TOKEN`, limited to `yednapg/homebrew-tap`

Never place a private key or certificate in Git, a release asset, the appcast, a cache, a manifest, or command output.

## Publishing

Create and push a signed, immutable tag first (`v0.0.2` or `v0.0.2-beta.1`). Then manually dispatch `.github/workflows/release.yml` for that exact tag. The workflow runs only on an Apple-silicon self-hosted runner and in the protected `production` environment.

The publish command is additionally fail-closed unless it sees GitHub Actions plus `BROCCOLI_ALLOW_PUBLISH=YES`. It verifies the signed tag and clean checkout, tests and benchmarks, builds with Developer ID and hardened runtime, validates nested signatures and production entitlements, privately notarizes and staples, creates and verifies the GitHub release, updates the Pages appcast, and finally updates `yednapg/homebrew-tap`.

The generated tap contains:

- `broccoli` for the newest stable archive
- `broccoli@beta` for the newest beta archive

Both casks are arm64-only, require macOS 26, declare `auto_updates true`, use an exact SHA-256, conflict with the other channel, and have narrowly scoped uninstall/zap entries.

Never replace an existing tag or ZIP. If an update is bad, publish a corrective release with a higher global build. If an archive is accidentally unshippable, publish a higher informational-only feed item that directs users to recovery instructions.

## Test matrix

The fast matrix runs `scripts/verify.sh` on the current macOS 27 Apple-silicon Mac. Before publication, repeat the local harness and Homebrew path on a clean macOS 26 arm64 VM or separate Mac.

For failure injection, preserve the installed baseline and test each condition independently: wrong archive key, wrong feed key, unsigned or changed appcast, changed signed notes, corrupt/truncated ZIP, incorrect enclosure length, wrong bundle ID or designated requirement, missing framework, invalid nested signature, unsupported minimum macOS, offline/DNS/timeout/redirect/server failure, interrupted download, cancellation at each cancellable stage, insufficient disk, read-only destination, standard-user authorization, termination during download, and relaunch failure. The pass condition is always the same: build 1 remains launchable and Broccoli shows an actionable branded error.

The OS/network/filesystem fault matrix needs a disposable VM because several cases require root-owned apps, artificial disk pressure, network interception, or destructive cask zap. CI gate variables must not be marked complete from unit tests alone.

