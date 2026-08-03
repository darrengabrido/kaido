#!/bin/zsh
set -euo pipefail

# Xcode Cloud runs this after cloning the repo, with the working directory
# set to ci_scripts/ itself — cd to the repo root before anything below
# relies on relative paths.
cd "$CI_PRIMARY_REPOSITORY_PATH"

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

# Xcode Cloud's Archive action runs with automatic package resolution
# disabled and expects a pre-existing Package.resolved — reasonable for a
# committed .xcodeproj, but this one is regenerated fresh every run and
# never had one to begin with. Resolve explicitly now, while automatic
# resolution is still allowed, so the Archive action finds a resolved file
# already in place instead of failing with "a resolved file is required".
xcodebuild -resolvePackageDependencies -project Kaido.xcodeproj
