# Releasing

ClaudeMeter ships as a signed, notarized `.dmg`. You don't build releases by
hand — a GitHub Actions workflow (`.github/workflows/build-dmg.yml`) does the
whole thing on a macOS runner: it builds the app, signs it with a Developer ID
certificate, notarizes it with Apple, packages the DMG, and publishes a GitHub
Release with the DMG attached.

Because the app is notarized, users can open the downloaded DMG without any
Gatekeeper warning — no right-click "Open Anyway", no `xattr` dance.

## When the workflow runs

The DMG is built in exactly these situations, and never for a feature branch:

| Trigger | Version / tag | Release type |
|---------|---------------|--------------|
| Push to `main` | `v<MARKETING_VERSION>-build.<run>` | Prerelease |
| Push a tag like `v1.0.0` | `v1.0.0` (the tag, verbatim) | Full release |
| "Run workflow" button with a version | `v<version>` | Full release |
| "Run workflow" button, version left blank | `v<MARKETING_VERSION>-build.<run>` | Prerelease |

The `push` trigger is filtered to `branches: [main]` and `tags: ['v*']`, so a
push to any other branch does not start the workflow. A second `if` guard on the
job (`github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')`)
keeps a manual dispatch from building off anything but `main` or a `v*` tag.

Prereleases derive their version from `MARKETING_VERSION` in the Xcode project
and append the run number so tags never collide. Full releases take their
version from the tag or the dispatch input.

## Cutting a specific version

Two ways to produce, say, `v1.0.0`:

**Push a git tag** (the conventional path):

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Or use the Actions UI:** GitHub → **Actions** → **Build DMG** → **Run
workflow** → type `1.0.0` in the version field → **Run workflow**.

Either one builds `ClaudeMeter-1.0.0.dmg` and publishes a full release tagged
`v1.0.0`.

> `MARKETING_VERSION` in the project is independent of the release tag. If you
> release `v1.0.0` while the project still says `1.0`, the DMG and release are
> named `1.0.0` but the app reports `1.0` internally. Bump `MARKETING_VERSION`
> in the Xcode project (both build configs in `project.pbxproj`) to keep them in
> sync.

## What the build does

The job runs these steps in order:

1. **Import the Developer ID certificate** into an ephemeral keychain created
   just for the run (deleted again on the way out).
2. **Build & sign** the app with `xcodebuild`, forcing
   `CODE_SIGN_IDENTITY="Developer ID Application"`, `ENABLE_HARDENED_RUNTIME=YES`
   (required for notarization), and a secure `--timestamp`. The signature is
   then checked with `codesign --verify --strict`.
3. **Notarize & staple the app** — zip it, `xcrun notarytool submit --wait`,
   then `xcrun stapler staple` the ticket into the bundle so it launches cleanly
   even offline.
4. **Package the DMG** by calling `scripts/create-dmg.sh` with `SKIP_BUILD=1`, so
   it packages the already-signed, already-stapled app instead of rebuilding.
5. **Notarize & staple the DMG** itself, then `stapler validate` it.
6. **Publish** — upload the DMG as a build artifact and create the GitHub
   Release (prerelease or full, per the table above).

Both the app *and* the DMG are stapled: the app so a copy dragged to
`/Applications` verifies without a network round-trip, the DMG so the download
opens without a Gatekeeper prompt.

## Required secrets

Configure these under **Settings → Secrets and variables → Actions**. The
workflow fails at the signing step until all five exist.

| Secret | What it is | Where to get it |
|--------|-----------|-----------------|
| `MACOS_CERTIFICATE` | base64 of the exported *Developer ID Application* `.p12` | see below |
| `MACOS_CERTIFICATE_PWD` | password set when exporting the `.p12` | you choose it at export time |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APPLE_ID` | Apple ID email used for notarization | your Apple Developer account email |
| `APPLE_APP_PASSWORD` | app-specific password for `notarytool` | [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |

### Exporting the certificate

1. Create a *Developer ID Application* certificate if you don't have one: Xcode →
   Settings → Accounts → select the team → **Manage Certificates** → **+** →
   *Developer ID Application*. (Creating this certificate type needs the
   **Account Holder** role.)
2. In **Keychain Access**, find `Developer ID Application: …`, expand it to
   confirm its private key is attached, right-click → **Export** → save a `.p12`
   and set a password. That password is `MACOS_CERTIFICATE_PWD`.
3. Base64-encode it and copy to the clipboard:

   ```bash
   base64 -i ClaudeMeter-DeveloperID.p12 | pbcopy
   ```

   Paste the result as the value of `MACOS_CERTIFICATE`. The workflow decodes it
   with `base64 --decode`, which tolerates the wrapped output.

## Why signing matters for this app

ClaudeMeter reads OAuth credentials from the login keychain (see
[authentication.md](authentication.md)). Keychain access is gated per
application by the item's access-control list, and macOS remembers an
"Always Allow" grant against the requesting app's **code signature**.

An ad-hoc signature changes on every build, so an "Always Allow" would not
survive an update — users would be re-prompted for keychain access each time
they upgrade. A stable Developer ID signature keeps the identity constant, so
the grant persists across versions. This is the practical reason the release
build is properly signed rather than ad-hoc.

## Building locally

The same scripts the CI uses also work on your machine, using your own automatic
signing:

```bash
# Build the Release app to build/Build/Products/Release/ClaudeMeter.app
./scripts/build-app.sh [version]

# Build the app and package it into a DMG in one shot
./scripts/create-dmg.sh [version]
```

`create-dmg.sh` accepts two environment hooks used by CI:

- `SKIP_BUILD=1` — skip `xcodebuild` and package the app already sitting in
  `build/`. Useful after a separate signed build.
- `XCODEBUILD_EXTRA_FLAGS` — extra settings appended to the `xcodebuild` call
  (defaults to empty, so local behavior is unchanged).

Packaging the DMG requires [`dmgbuild`](https://pypi.org/project/dmgbuild/)
(`pip install dmgbuild`); the CI installs it on the runner. DMG layout lives in
`scripts/dmg-settings.py`.
