# Build-to-TestFlight pipeline

How a push to `master` becomes a TestFlight build, written so the same pipeline can be
dropped into another iOS repo (Ghost, Gab, Pupsteps, …) in an afternoon. Everything here was
read from the workflows and scripts in this repo and cross-checked against the Actions run
history on Sept 4, 2026.

## Which path actually ships builds

Two paths are wired up. Only one has a verified record of succeeding.

| Path | Files | Trigger | Verified |
| --- | --- | --- | --- |
| **GitHub Actions** | `.github/workflows/ios-build.yml`, `.github/workflows/testflight.yml` | Every push and PR builds; pushes to `master` also archive and upload | Yes. `Deploy to TestFlight` succeeded on every `master` push checked (runs 36, 37, 39 on Aug 24 and Aug 29). |
| **Xcode Cloud** | `ci_scripts/ci_post_clone.sh` | Configured in App Store Connect, not in the repo | Not from here. The post-clone script exists and mirrors the Actions setup, but Xcode Cloud run history is not visible from the repository. Treat it as an unproven parallel path. |

**Recommendation for other apps: port the GitHub Actions path.** It is self-contained in the
repo, every step is inspectable, and it has a green history. Keep Xcode Cloud only if you
already rely on it somewhere. Running both means two secret sets to keep in sync.

## The two workflows

### `iOS Build` (`ios-build.yml`)

Runs on every push, every PR, and manual dispatch. No signing, no upload. It is the compile
check and the unit-test runner.

1. macOS 26 runner, `xcode-select` to Xcode 26.5.
2. `brew install xcodegen`.
3. Writes a throwaway `Config/Secrets.xcconfig` with placeholder values. The app must build
   with placeholders, which it does because every service (Supabase, OpenAI, Spotify) is
   optional at runtime.
4. Writes `~/.netrc` with the Mapbox downloads token so SwiftPM can fetch Mapbox's binary
   packages. **This is the only secret the build check needs.**
5. `xcodegen generate`.
6. Asserts every target has an Info.plist or `GENERATE_INFOPLIST_FILE`, because the build below
   runs with signing off and would otherwise hide a signing failure until someone opens Xcode.
7. `xcodebuild build` for the generic iOS Simulator destination, `CODE_SIGNING_ALLOWED=NO`.
8. `xcodebuild test` on an iPhone 17 simulator.

Concurrency is grouped per branch with `cancel-in-progress: true`, so a rapid second push
cancels the first run. That is why some `master` runs show as cancelled in the history: a
later push superseded them, not a failure.

### `Deploy to TestFlight` (`testflight.yml`)

Runs on pushes to `master` and manual dispatch. Uses the `testflight` GitHub Environment, so
environment-level secrets shadow repo-level ones of the same name.

1. Same runner, Xcode, and XcodeGen setup as above, plus an SwiftPM cache keyed on
   `project.yml`.
2. **Validate deployment secrets.** Fails fast with a named error if any of the twelve
   secrets below is empty.
3. **Create app configuration.** Writes the real `Config/Secrets.xcconfig` from secrets.
   `OPENAI_API_KEY` is written empty on purpose: the app now takes a rider-supplied key from
   the Companion settings screen instead of shipping one in the binary.
4. Mapbox `~/.netrc`, as above.
5. **Install signing certificate and profile.** Decodes the base64 `.p12` and
   `.mobileprovision`, creates a temporary keychain, imports the cert, installs the profile,
   and appends manual-signing settings to the xcconfig. Signing is scoped through the xcconfig
   rather than the `xcodebuild` command line because SwiftPM resource bundles reject a
   globally applied provisioning profile.
6. **Configure App Store Connect API key.** Trims whitespace from the key and issuer IDs
   (paste artifacts break JWT auth), accepts the `.p8` as raw PEM or with literal `\n`, and
   installs it in every directory `altool` might look in.
7. **Verify App Store Connect API auth.** Runs `altool --list-apps` and checks the app is
   visible to the key before spending ten minutes on an archive.
8. **Generate Xcode project** and stamp `CFBundleVersion` with a UTC timestamp
   (`YYYYMMDDHHMM`) using PlistBuddy. XcodeGen writes its own literal build number into
   `Info.plist`, so a build-setting override never reaches the archive; stamping the generated
   file after `xcodegen` is the only thing that works. A follow-up step verifies the stamp took.
9. **Archive** for `generic/platform=iOS`, Release, with the temporary keychain.
10. **Export IPA** with an `app-store-connect` export options plist, manual signing.
11. **Upload to TestFlight** with `altool --upload-package`, passing the app's Apple ID and
    bundle ID explicitly. The legacy `--upload-app` looks the Apple ID up from the bundle ID
    and returns a misleading 401 when that lookup fails. A 401 here is diagnosed in the log
    as a Team API key problem, never a workflow bug.
12. **Clean up** the temporary keychain, always.

## Secrets

Twelve secrets, all under **Settings → Secrets and variables → Actions** (or the
`testflight` environment). One is shared with `iOS Build`.

| Secret | Used by | What it is |
| --- | --- | --- |
| `MAPBOX_DOWNLOADS_TOKEN` | both | Secret `sk.` token with `DOWNLOADS:READ`. Needed just to compile. |
| `APPLE_TEAM_ID` | deploy | Ten-character team ID. |
| `MAPBOX_ACCESS_TOKEN` | deploy | Public `pk.` token the app uses at runtime. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | deploy | Base64 of the Apple Distribution `.p12`. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | deploy | Password set when exporting the `.p12`. |
| `APP_STORE_PROVISIONING_PROFILE_BASE64` | deploy | Base64 of the App Store `.mobileprovision`. |
| `APP_STORE_CONNECT_KEY_ID` | deploy | App Store Connect API **Team** key ID. Individual keys do not work with `altool`. |
| `APP_STORE_CONNECT_ISSUER_ID` | deploy | Issuer ID from the same page. |
| `APP_STORE_CONNECT_API_KEY` | deploy | Full `.p8` contents including the BEGIN and END lines. |
| `SUPABASE_HOST` | deploy | Bare host, no `https://`. xcconfig treats `//` as a comment. |
| `SUPABASE_ANON_KEY` | deploy | Anon key. |
| `SPOTIFY_CLIENT_ID` | deploy | Spotify app client ID. |

Two hard-coded values live in `testflight.yml`'s `env:` block, not in secrets:
`APP_BUNDLE_ID` and `ASC_APP_APPLE_ID` (the numeric App Store Connect "Apple ID" of the app).

## Porting checklist for another app

Assumes the other app is also XcodeGen-based. If it has a checked-in `.xcodeproj`, drop the
`xcodegen` steps and the Info.plist stamping changes to a plain `-showBuildSettings` /
`agvtool` flow.

1. Copy both workflow files. Replace every `Kaido` in scheme, project, archive, and IPA
   names, and set `APP_BUNDLE_ID` and `ASC_APP_APPLE_ID`.
2. Create the app record in App Store Connect first. The `--list-apps` check needs it to
   exist.
3. In the Apple Developer portal, create one Apple Distribution certificate (reusable across
   apps on the same team) and one App Store provisioning profile per app. The profile must
   include every capability the app declares (Kaido's needs iCloud, push, Sign in with Apple).
4. Create a Team API key in App Store Connect with Admin or App Manager role. Download the
   `.p8` immediately; Apple only offers it once.
5. Add the twelve secrets. For the base64 ones: `base64 -i file | pbcopy`.
6. Rewrite the "Create app configuration" step for the other app's own `Secrets.xcconfig`
   keys, and the "Validate deployment secrets" list to match.
7. Push to a branch and run `iOS Build` first. Only once that is green, merge to `master` or
   dispatch `Deploy to TestFlight` manually.

## Kaido-specific parts that will not transfer

- **Mapbox.** The `~/.netrc` step and `MAPBOX_DOWNLOADS_TOKEN` only exist because Mapbox
  ships its SDKs as authenticated binary packages. An app without Mapbox deletes the step
  and the secret.
- **The Info.plist stamping workaround.** Needed because XcodeGen's `info.properties` merge
  overrides `$(CURRENT_PROJECT_VERSION)`. A project that manages `Info.plist` differently
  may not need it, but keep the "verify the stamp took" step regardless; a duplicate build
  number is the most common upload rejection.
- **The Spotify client ID check** in the upload step reads a Kaido-specific Info.plist key.
  Delete it or point it at whichever runtime value the other app cannot live without.
- **`ENABLE_USER_SCRIPT_SANDBOXING: NO`** and the entitlements block in `project.yml` are
  Kaido's capabilities, not pipeline requirements.
- **Empty `OPENAI_API_KEY`.** Only relevant to apps that once compiled a model key in.

## Things that bit us, so you don't repeat them

- Individual App Store Connect API keys fail every `altool` call with 401. Only Team keys.
- Whitespace pasted into the key ID or issuer ID secret silently breaks JWT signing. The
  workflow trims; do the same anywhere else you read them.
- An environment secret with the same name as a repo secret wins. When a value "should be
  right" and isn't, check **Settings → Environments → testflight**.
- `CODE_SIGNING_ALLOWED=NO` hides missing-Info.plist failures. The explicit target check
  exists for that reason.
- `cancel-in-progress` on the deploy workflow would let a fast second push cancel an upload
  mid-flight. It is `false` there on purpose and `true` on the build check.
