#!/bin/zsh
set -euo pipefail

# Xcode Cloud runs this after cloning the repo, with the working directory
# set to ci_scripts/ itself — cd to the repo root before anything below
# relies on relative paths.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Xcode Cloud's Environment Variables UI (like most secret-paste fields) can
# silently introduce leading/trailing whitespace or a stray newline, which
# breaks token auth without changing how the value looks on screen — the
# same class of bug already fixed for the App Store Connect Key ID/Issuer ID
# in testflight.yml. Trim before validating, so a whitespace-only value is
# correctly caught as "missing" rather than producing a broken credential.
for name in APPLE_TEAM_ID MAPBOX_ACCESS_TOKEN MAPBOX_DOWNLOADS_TOKEN SUPABASE_HOST SUPABASE_ANON_KEY SPOTIFY_CLIENT_ID; do
  typeset -g "$name=$(printf '%s' "${(P)name:-}" | tr -d '[:space:]')"
done

# Fail fast with a clear message instead of a bare "unbound variable" crash
# or, worse, a confusing Swift Package resolution error further downstream.
# Mirrors testflight.yml's "Validate deployment secrets" step, minus the
# Apple Distribution cert/profile/API-key vars — Xcode Cloud manages signing
# and TestFlight upload itself, so those have no equivalent here.
missing=0
for name in APPLE_TEAM_ID MAPBOX_ACCESS_TOKEN MAPBOX_DOWNLOADS_TOKEN SUPABASE_HOST SUPABASE_ANON_KEY SPOTIFY_CLIENT_ID; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "error: Missing required Xcode Cloud environment variable: $name. Add it under this workflow's Environment tab in App Store Connect (mark it Secret)." >&2
    missing=1
  fi
done
if [[ "$missing" -eq 1 ]]; then
  exit 1
fi

brew install xcodegen

# Mirrors .github/workflows/testflight.yml's "Create app configuration" step.
# CODE_SIGN_STYLE defaults to Automatic — leave the CODE_SIGN_STYLE
# environment variable unset on the workflow unless you specifically want to
# opt back into the manual keychain-based signing GitHub Actions needs;
# Automatic lets Xcode Cloud manage certs and profiles itself.
{
  echo "DEVELOPMENT_TEAM = $APPLE_TEAM_ID"
  echo "MAPBOX_ACCESS_TOKEN = $MAPBOX_ACCESS_TOKEN"
  echo "SUPABASE_HOST = $SUPABASE_HOST"
  echo "SUPABASE_ANON_KEY = $SUPABASE_ANON_KEY"
  echo "SPOTIFY_CLIENT_ID = $SPOTIFY_CLIENT_ID"
  echo "CODE_SIGN_STYLE = ${CODE_SIGN_STYLE:-Automatic}"
  # Intentionally always blank — see README's TestFlight deployment section.
  echo "OPENAI_API_KEY ="
} > Config/Secrets.xcconfig

# Mapbox's binary SPM dependencies require an authenticated download even to
# resolve packages, same as the GitHub Actions "Configure Mapbox SDK
# downloads" step.
{
  echo "machine api.mapbox.com"
  echo "login mapbox"
  echo "password $MAPBOX_DOWNLOADS_TOKEN"
} > "$HOME/.netrc"
chmod 0600 "$HOME/.netrc"

# Belt-and-suspenders: also register the same credential in the login
# keychain. GitHub Actions resolves these same binary targets fine with only
# .netrc, but Xcode Cloud's build system has 403'd on every Mapbox binary
# target across every token value, Xcode version, and cache state tried so
# far — which points at .netrc specifically not reaching the sandboxed
# subprocess that downloads binary targets (as opposed to the plain `git`
# subprocess used for source dependencies, which has worked every time).
# Apple's URL loading system also checks the keychain for matching Internet
# passwords, a separate code path from .netrc. Best-effort: never fail the
# build over this.
security add-internet-password -a mapbox -s api.mapbox.com -w "$MAPBOX_DOWNLOADS_TOKEN" -U 2>/dev/null || true

# Diagnostic only — does not gate the build. Proves or rules out the token
# itself independent of Xcode's own downloader, by hitting the exact URL
# that's been failing, once via .netrc and once with explicit Basic auth.
MAPBOX_PROBE_URL="https://api.mapbox.com/downloads/v2/mapbox-common/releases/ios/packages/24.27.0/MapboxCommon.zip"
echo "Mapbox auth probe (diagnostic, not build-blocking):"
echo "  curl -n (netrc):        HTTP $(curl -s -o /dev/null -w '%{http_code}' -n "$MAPBOX_PROBE_URL" || echo curl-error)"
echo "  curl -u (explicit auth): HTTP $(curl -s -o /dev/null -w '%{http_code}' -u "mapbox:$MAPBOX_DOWNLOADS_TOKEN" "$MAPBOX_PROBE_URL" || echo curl-error)"

# The .xcodeproj isn't checked into git — Xcode Cloud needs it generated
# fresh on every clone, same as the GitHub Actions "Generate Xcode project"
# step.
xcodegen generate

# Xcode Cloud persists SPM's package cache across separate builds, including
# ones that failed mid-download — a prior run dying partway through fetching
# Mapbox's authenticated binary frameworks can leave a corrupt/incomplete
# artifact behind that every subsequent resolve trips over identically.
# Clear both documented SPM cache locations so each run resolves clean.
rm -rf "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm"

# Xcode Cloud's build machines ship with these two Xcode user defaults
# pre-set, which block ANY package resolution — including this script's own
# explicit call below — until a Package.resolved already exists. That's a
# dead end for a project whose .xcodeproj is regenerated fresh every run and
# never has one. Clearing them is Apple's own documented workaround (see
# https://github.com/apple/swift-package-manager/issues/6914); delete is a
# no-op if a given key isn't actually set, hence the fallback to true.
defaults delete com.apple.dt.Xcode IDEPackageOnlyUseVersionsFromResolvedFile 2>/dev/null || true
defaults delete com.apple.dt.Xcode IDEDisableAutomaticPackageResolution 2>/dev/null || true

xcodebuild -resolvePackageDependencies -project Kaido.xcodeproj
