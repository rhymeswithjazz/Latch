# Personal Mac releases

Latch follows the personal HighDock release process. Universal ZIPs live at [rhymeswithjazz/Latch releases](https://github.com/rhymeswithjazz/Latch/releases). Sparkle uses [the Latch feed](https://rhymeswithjazz.github.io/Latch/appcast.xml). Stable and beta releases share that feed; beta entries use Sparkle's `beta` channel.

The existing bundle identifier, `com.rhymeswithjazz.Unlocker`, stays unchanged so preferences and login registration keep their identity. The signing team is `T4VMW3KDVX`. Distribution builds enable updates; `scripts/build.sh` and CI builds leave them disabled. A delegate fixes the feed URL so a saved preference cannot redirect it. Latch sends no Sparkle system profile, and downloading updates does not enable automatic installation.

## Signing setup

This Mac reuses NetNewsWire's Developer ID Application certificate and `netnewswire-notary` Keychain profile. Those credentials belong to the Apple developer account, not to NetNewsWire. No certificate, password, or private update key goes in the repository or GitHub Actions.

Latch has a separate Sparkle key stored in the login Keychain under account `com.rhymeswithjazz.Latch`. Only the public key appears in `Resources/Info.plist`. Preserve that key when moving release work to another Mac. Do not generate a replacement key for an already distributed app.

To resolve the exact Sparkle version pinned by `Package.resolved`:

```sh
python3 scripts/personal_release.py setup
```

The one-time `setup --create-key` command creates the key and embeds its public half if no public key is configured. If a public key already exists, it checks for the matching private key instead of replacing it. To transfer the key securely, use Sparkle's `generate_keys --help` for its export and import options. Keep exports outside this repository.

On another release Mac, import the same Developer ID certificate with its private key and the original Sparkle key. Store Apple notarization credentials interactively:

```sh
xcrun notarytool store-credentials netnewswire-notary --apple-id YOUR_APPLE_ID --team-id T4VMW3KDVX
```

Use the prompt for the app-specific password. `--notary-profile NAME` can select a different Keychain profile. `--sparkle-bin PATH` can select an existing copy of the pinned Sparkle tools.

```sh
python3 scripts/personal_release.py preflight
```

Preflight checks the Developer ID identity, update key, notarization credentials, and public GitHub repository. Keychain may ask for access when Apple's signing tools or Sparkle first use a key.

## Package a release

Commit the source first. The first Sparkle distribution build is `8`; builds `1` through `7` belong to the prototypes. Increase build numbers across both stable and beta releases. Use a three-part marketing version such as `0.1.0`.

```sh
python3 scripts/personal_release.py package \
  --version 0.1.0 --build 8 --notes docs/releases/0.1.0.md
```

Add `--beta` for a test release. The command:

1. Builds Apple Silicon and Intel executables and combines them into one app.
2. Embeds Sparkle with its symlinks and executable permissions intact.
3. Signs its helper tools, services, framework, and app with Developer ID and hardened runtime.
4. Submits the app to Apple, checks acceptance, staples the ticket, and verifies Gatekeeper.
5. Creates a ZIP, signs it with Sparkle, verifies that signature, and records artifact hashes with the exact source commit.

Files are written to `build/personal/releases/BUILD/`. `build.log` holds compiler output, `notarization.json` holds Apple's result, and `export/Latch.app` is the app to test. A failed run keeps its files for diagnosis; move that build directory aside before retrying. Never replace an artifact that has been published.

Packaging does not publish anything on GitHub. It uploads the app only to Apple's notarization service. The notarized ZIP can also be copied directly to another Mac without waiting for a GitHub release.

## Draft and publish

Review the app and release notes, then push the recorded commit to `main`. Create `personal-BUILD` at the exact `commit` recorded in `release.json` and push that tag through your Git SSH connection. Do not retag the current branch tip if it differs from the packaged commit. Then upload a draft:

```sh
python3 scripts/personal_release.py draft build/personal/releases/8
```

This checks the artifact hashes and verifies the remote tag points to the packaged commit, then creates a **draft** release at that existing tag with the ZIP and its appcast. If the tag is missing, the command prints the exact tag and push commands to run. Using an existing tag with `--verify-tag` avoids asking the release API to create a ref at an older workflow-bearing commit; no extra OAuth `workflow` permission is needed. Review it on GitHub, then publish it. Keep the prerelease checkbox consistent with the `--beta` packaging choice.

The **Personal update feed** workflow rebuilds the feed from published `personal-*` releases. It verifies matching tags, archive URLs, sizes, channels, signature format, and unique build numbers before deployment. Private signing keys stay on the release Mac. The ZIP's cryptographic signature is verified during packaging and again by Sparkle on the receiving Mac.

The workflow publishes through GitHub Pages using Actions. The `github-pages` deployment environment must allow `main` and `personal-*` tags. Run the workflow manually once to create a valid empty feed before the first release. Deleting a release and rerunning the workflow removes its feed entry; it does not downgrade installed apps.

## Install on another Mac

1. Download the notarized ZIP from the release or copy the locally packaged ZIP.
2. Quit any running Latch, unzip, and move `Latch.app` to `/Applications`.
3. Open it and select and calibrate the Watch for that Mac. Set Launch at Login after placing it in its permanent location.
4. Use **Check for Updates** in the menu bar. Enable **Include Test Builds** only if you want beta releases too.

Settings stay local to each Mac. Installing an update preserves `~/Library/Application Support/Unlocker/configuration.json` and the app's preferences. The old development app cannot bootstrap itself through Sparkle; install the first distribution build manually.

## Validation

```sh
python3 -m unittest discover -s scripts/tests
./scripts/test.sh
./scripts/build.sh --universal
```

CI checks the release scripts, Swift behavior, universal build, and bundle signature. Its downloadable development ZIP is ad-hoc signed and has updates disabled. Use the notarized release ZIP for other machines.

Before relying on automatic installation, install release A on a second Mac, save a Watch and threshold, publish a higher release B, and check for updates. Confirm installation, settings preservation, and stable/beta selection. Check a modified ZIP against a local test feed; Sparkle must reject it. Never upload the modified ZIP to the production feed.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/), [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). The release tooling was adapted from the personal HighDock scripts.
