# Distribution

Use [Personal releases](PersonalReleases.md) for the current build, signing, notarization, draft release, and Sparkle feed workflow. Signing keys stay on the release Mac. GitHub Actions runs tests and builds, and deploys the appcast from published releases.

Builds 1 through 7 are historical prototypes. Their artifacts and validation notes remain local under `build/prototypes/`. The first Sparkle distribution build is 8. Install it manually to receive future updates.

The old `notarize_prototype.py` tool remains available for local prototypes with updates disabled. Do not publish those ZIPs to the Sparkle feed.
