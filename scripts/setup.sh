#!/usr/bin/env bash
#
# One-shot setup for a freshly cloned Kaido checkout:
#
#   1. checks Xcode and installs XcodeGen if needed
#   2. creates Config/Secrets.xcconfig (gitignored) from the template
#   3. registers the Mapbox downloads credential in ~/.netrc
#   4. generates Kaido.xcodeproj and resolves the Swift packages
#
# Safe to re-run: values already filled in are left alone, and only blanks or
# leftover template placeholders are asked about.
#
#   scripts/setup.sh [--non-interactive] [--reconfigure] [--skip-resolve] [--open]

# Re-exec under bash if someone runs this with `sh scripts/setup.sh` — `pipefail`
# and BASH_SOURCE below aren't POSIX.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SECRETS_FILE="Config/Secrets.xcconfig"
SECRETS_TEMPLATE="Config/Secrets.xcconfig.example"
NETRC="$HOME/.netrc"
XCODEPROJ="Kaido.xcodeproj"
MIN_XCODE_MAJOR=26

INTERACTIVE=1
RECONFIGURE=0
SKIP_RESOLVE=0
OPEN_XCODE=0
WARNINGS=()

# ---------------------------------------------------------------- output ----

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
  YELLOW=$'\033[33m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; YELLOW=""; GREEN=""; RESET=""
fi

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info() { printf '    %s\n' "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
ok()   { printf '    %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$1"; WARNINGS+=("$1"); }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Set up a freshly cloned Kaido checkout.

Usage: scripts/setup.sh [options]

Options:
  --non-interactive   Never prompt; take values from the environment instead.
  --reconfigure       Ask about every setting, including ones already filled in.
  --skip-resolve      Don't run `xcodebuild -resolvePackageDependencies`.
  --open              Open Kaido.xcodeproj when setup finishes.
  -h, --help          Show this help.

Environment variables (used as answers, required with --non-interactive):
  DEVELOPMENT_TEAM / APPLE_TEAM_ID   10-character Apple Team ID
  MAPBOX_ACCESS_TOKEN                Public "pk." token used by the app at runtime
  MAPBOX_DOWNLOADS_TOKEN             Private "sk." token with DOWNLOADS:READ, for ~/.netrc
  SUPABASE_HOST, SUPABASE_ANON_KEY   Optional — enables sign-in and Ride Together
  OPENAI_API_KEY                     Optional — AI blurbs in free-ride discover
  SPOTIFY_CLIENT_ID                  Optional — Spotify playback controls
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) INTERACTIVE=0 ;;
    --reconfigure)     RECONFIGURE=1 ;;
    --skip-resolve)    SKIP_RESOLVE=1 ;;
    --open)            OPEN_XCODE=1 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

# Prompting needs a terminal on stdin — piping the script in (`curl … | bash`)
# would otherwise consume the script itself as answers.
[[ -t 0 ]] || INTERACTIVE=0

# --------------------------------------------------------------- helpers ----

# Secrets are pasted by hand, and a stray newline or trailing space silently
# breaks token auth without changing how the value looks. None of these values
# legitimately contain whitespace, so drop all of it (same as ci_post_clone.sh).
strip_ws() { printf '%s' "${1//[[:space:]]/}"; }

mask() {
  local value="$1"
  if [[ ${#value} -le 10 ]]; then printf '%s' "$value"; else printf '%s…' "${value:0:6}"; fi
}

# Identifiers are worth echoing in full so typos are obvious; keys and tokens
# aren't — they end up in scrollback and screen shares.
display_value() {
  case "$1" in
    DEVELOPMENT_TEAM|SUPABASE_HOST|SPOTIFY_CLIENT_ID) printf '%s' "$2" ;;
    *) mask "$2" ;;
  esac
}

# Values still carrying the template's fill-me-in text, which the app itself
# treats as "not configured" (see KaidoSupabaseClient.isPlaceholder).
is_placeholder() {
  case "$1" in
    ""|YOURTEAMID1|*your_*|*your-project-ref*|*_here) return 0 ;;
  esac
  return 1
}

# Reads an answer. Prompts go to stderr so callers can capture stdout.
ask() {
  local prompt="$1" default="${2:-}" reply=""
  if [[ $INTERACTIVE -eq 0 ]]; then
    printf '%s' "$default"
    return 0
  fi
  if [[ -n "$default" ]]; then
    read -r -p "    $prompt [$(mask "$default")]: " reply || true
  else
    read -r -p "    $prompt (blank to skip): " reply || true
  fi
  reply="$(strip_ws "$reply")"
  printf '%s' "${reply:-$default}"
}

confirm() {
  local prompt="$1" reply=""
  [[ $INTERACTIVE -eq 1 ]] || return 1
  read -r -p "    $prompt [y/N]: " reply || true
  [[ "$reply" == [yY]* ]]
}

# Key/value access for xcconfig files. Both pass the key and value through the
# environment rather than interpolating them into the awk program, so tokens
# containing slashes, ampersands or backslashes can't corrupt the file.
get_config_value() {
  KAIDO_KEY="$1" awk '
    BEGIN { key = ENVIRON["KAIDO_KEY"] }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]+$", "")
      print; exit
    }
  ' "$2"
}

set_config_value() {
  local key="$1" value="$2" file="$3" tmp
  tmp="$(mktemp)"
  KAIDO_KEY="$key" KAIDO_VALUE="$value" awk '
    BEGIN { key = ENVIRON["KAIDO_KEY"]; value = ENVIRON["KAIDO_VALUE"]; written = 0 }
    !written && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      print key " = " value; written = 1; next
    }
    { print }
    END { if (!written) print key " = " value }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# ------------------------------------------------------ 1. prerequisites ----

check_prerequisites() {
  step "Checking prerequisites"

  [[ "$(uname -s)" == "Darwin" ]] || die "Kaido is an iOS app — setup only runs on macOS."

  command -v xcodebuild >/dev/null 2>&1 || die "Xcode not found. Install Xcode $MIN_XCODE_MAJOR or newer from the App Store."

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$developer_dir" != *"/Xcode"*"/Developer"* ]]; then
    die "xcode-select points at '${developer_dir:-nothing}', not a full Xcode install.
       Fix it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi

  local version_output
  if ! version_output="$(xcodebuild -version 2>&1)"; then
    die "xcodebuild failed — you may need to accept the license first:
       sudo xcodebuild -license accept
       $version_output"
  fi

  local xcode_version xcode_major
  xcode_version="$(printf '%s' "$version_output" | awk '/^Xcode/ { print $2; exit }')"
  xcode_major="${xcode_version%%.*}"
  if [[ -n "$xcode_major" && "$xcode_major" -lt "$MIN_XCODE_MAJOR" ]]; then
    # The app targets iOS 26 and the entitlements/APIs it uses won't compile on older SDKs.
    die "Xcode $xcode_version found, but Kaido needs Xcode $MIN_XCODE_MAJOR or newer."
  fi
  ok "Xcode $xcode_version"

  if command -v xcodegen >/dev/null 2>&1; then
    ok "XcodeGen $(xcodegen --version 2>/dev/null | tail -n 1 | sed 's/^Version: *//')"
  else
    if ! command -v brew >/dev/null 2>&1; then
      die "XcodeGen is missing and Homebrew isn't installed.
       Install it from https://github.com/yonaskolb/XcodeGen, then re-run this script."
    fi
    if [[ $INTERACTIVE -eq 1 ]] && ! confirm "XcodeGen is missing. Install it with Homebrew?"; then
      die "XcodeGen is required — the .xcodeproj is generated from project.yml, not committed."
    fi
    info "Installing XcodeGen…"
    brew install xcodegen
    ok "XcodeGen installed"
  fi
}

# ------------------------------------------------------------ 2. secrets ----

# configure_key <XCCONFIG_KEY> <ENV_VAR> <PROMPT>
configure_key() {
  local key="$1" env_var="$2" prompt="$3"
  local current env_value default value normalized

  current="$(get_config_value "$key" "$SECRETS_FILE")"
  env_value="$(strip_ws "${!env_var:-}")"

  if [[ -n "$env_value" ]]; then
    value="$env_value"
    note "$key taken from \$$env_var"
  elif [[ $RECONFIGURE -eq 0 ]] && ! is_placeholder "$current"; then
    # A value that's already on disk still gets checked — a hand-edited file is
    # exactly where a "https://…" host or a pasted-in newline comes from.
    value="$(normalize_value "$key" "$(strip_ws "$current")")"
    if [[ "$value" == "$current" ]]; then
      ok "$key already set ($(display_value "$key" "$current"))"
      validate_value "$key" "$current"
      return 0
    fi
    note "$key needed cleaning up"
  else
    default=""
    is_placeholder "$current" || default="$current"
    value="$(strip_ws "$(ask "$prompt" "$default")")"
  fi

  value="$(normalize_value "$key" "$value")"
  is_placeholder "$value" && value=""
  validate_value "$key" "$value"
  set_config_value "$key" "$value" "$SECRETS_FILE"

  if [[ -n "$value" ]]; then
    ok "$key set ($(display_value "$key" "$value"))"
  else
    note "$key left blank"
  fi
}

# Fixes up a value before it's validated and written, so the checks below see
# what will actually reach the build.
normalize_value() {
  local key="$1" value="$2"
  case "$key" in
    SUPABASE_HOST)
      # Must be the bare host: xcconfig treats "//" as a comment marker, so
      # "https://abc.supabase.co" would silently truncate to "https:". The app
      # adds the scheme itself.
      value="${value#http://}"
      value="${value#https://}"
      value="${value%%/*}"
      ;;
  esac
  printf '%s' "$value"
}

validate_value() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || return 0

  # xcconfig treats "//" as a comment marker, so anything after it is silently
  # dropped from the built Info.plist — a broken value that still looks right here.
  case "$value" in
    *//*) warn "$key contains '//', which xcconfig reads as a comment and truncates." ;;
  esac

  case "$key" in
    DEVELOPMENT_TEAM)
      [[ "$value" =~ ^[A-Z0-9]{10}$ ]] ||
        warn "DEVELOPMENT_TEAM should be a 10-character Apple Team ID (got '$value')."
      ;;
    MAPBOX_ACCESS_TOKEN)
      case "$value" in
        sk.*) warn "MAPBOX_ACCESS_TOKEN looks like a secret 'sk.' token. Use the public 'pk.' token here — this one ends up in the app's Info.plist." ;;
        pk.*) : ;;
        *)    warn "MAPBOX_ACCESS_TOKEN doesn't start with 'pk.' — check you copied the public token." ;;
      esac
      ;;
    SUPABASE_ANON_KEY)
      # Best-effort: decode the JWT payload and refuse to ship a service_role key,
      # which would hand every app install full read/write past RLS.
      local payload
      payload="$(printf '%s' "$value" | cut -d. -f2 | tr '_-' '/+')" || true
      payload="$(printf '%s==' "$payload" | base64 -d 2>/dev/null || true)"
      case "$payload" in
        *service_role*) warn "SUPABASE_ANON_KEY looks like a service_role key — use the 'anon'/'public' key instead." ;;
      esac
      ;;
  esac
}

configure_secrets() {
  step "Configuring $SECRETS_FILE"

  if [[ ! -f "$SECRETS_FILE" ]]; then
    [[ -f "$SECRETS_TEMPLATE" ]] || die "Missing $SECRETS_TEMPLATE — is this a complete checkout?"
    cp "$SECRETS_TEMPLATE" "$SECRETS_FILE"
    # Blank the template's fill-me-in values up front: a leftover placeholder
    # OpenAI key would send real (failing) requests, where an empty one just
    # turns the feature off.
    local key current
    for key in DEVELOPMENT_TEAM MAPBOX_ACCESS_TOKEN SUPABASE_HOST SUPABASE_ANON_KEY OPENAI_API_KEY SPOTIFY_CLIENT_ID; do
      current="$(get_config_value "$key" "$SECRETS_FILE")"
      is_placeholder "$current" && set_config_value "$key" "" "$SECRETS_FILE"
    done
    ok "Created from the template"
  else
    ok "Already exists — keeping the values that are filled in"
  fi
  chmod 600 "$SECRETS_FILE"

  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO_ROOT" check-ignore -q "$SECRETS_FILE" ||
      warn "$SECRETS_FILE is NOT gitignored — do not commit it."
  fi

  # APPLE_TEAM_ID is what CI calls it; accept either name.
  : "${DEVELOPMENT_TEAM:=${APPLE_TEAM_ID:-}}"

  info "Required for the app to build and the map to render:"
  configure_key DEVELOPMENT_TEAM    DEVELOPMENT_TEAM    "Apple Team ID (10 chars, from developer.apple.com → Membership)"
  configure_key MAPBOX_ACCESS_TOKEN MAPBOX_ACCESS_TOKEN "Mapbox public token 'pk.…' (account.mapbox.com/access-tokens)"

  info ""
  info "Optional — leave blank to build without them:"
  configure_key SUPABASE_HOST     SUPABASE_HOST     "Supabase host, no https:// (sign-in, Ride Together)"
  configure_key SUPABASE_ANON_KEY SUPABASE_ANON_KEY "Supabase anon/public key"
  configure_key OPENAI_API_KEY    OPENAI_API_KEY    "OpenAI API key (AI blurbs in free-ride discover)"
  configure_key SPOTIFY_CLIENT_ID SPOTIFY_CLIENT_ID "Spotify client ID (redirect URI kaido://spotify-callback)"

  if [[ -z "$(get_config_value DEVELOPMENT_TEAM "$SECRETS_FILE")" ]]; then
    warn "No DEVELOPMENT_TEAM: signed builds (device, archive) will fail. Simulator builds still work with CODE_SIGNING_ALLOWED=NO."
  fi
}

# ---------------------------------------------- 3. Mapbox downloads token ----

configure_mapbox_downloads() {
  step "Configuring the Mapbox SDK download credential"

  if [[ -f "$NETRC" ]] && grep -q '^[[:space:]]*machine[[:space:]]\{1,\}api\.mapbox\.com' "$NETRC"; then
    ok "~/.netrc already has an api.mapbox.com entry"
    note "Edit ~/.netrc by hand if that token is stale."
    return 0
  fi

  info "Mapbox's SDKs are binary Swift packages behind an authenticated download,"
  info "so a private token with the DOWNLOADS:READ scope is needed just to build."
  note "Create one at https://account.mapbox.com/access-tokens (it starts with 'sk.')."

  local token
  token="$(strip_ws "$(ask "Mapbox downloads token 'sk.…'" "$(strip_ws "${MAPBOX_DOWNLOADS_TOKEN:-}")")")"

  if [[ -z "$token" ]]; then
    warn "No Mapbox downloads token — Swift package resolution will fail with a 403 until ~/.netrc has one."
    return 0
  fi
  case "$token" in
    pk.*) warn "That's the public 'pk.' token; downloads need a secret 'sk.' token with DOWNLOADS:READ." ;;
    sk.*) : ;;
    *)    warn "Mapbox downloads tokens normally start with 'sk.' — double-check the scope." ;;
  esac

  if [[ -f "$NETRC" ]]; then
    local backup="$NETRC.kaido-backup-$(date +%Y%m%d%H%M%S)"
    cp "$NETRC" "$backup"
    note "Backed up the existing ~/.netrc to $(basename "$backup")"
    # netrc entries are newline-sensitive; make sure we don't glue ours onto a
    # file that doesn't end in one.
    [[ -z "$(tail -c 1 "$NETRC")" ]] || printf '\n' >> "$NETRC"
  fi

  {
    printf 'machine api.mapbox.com\n'
    printf 'login mapbox\n'
    printf 'password %s\n' "$token"
  } >> "$NETRC"
  chmod 600 "$NETRC"
  ok "Added the api.mapbox.com entry to ~/.netrc"
}

# --------------------------------------------------- 4. project + packages ---

generate_project() {
  step "Generating $XCODEPROJ"
  xcodegen generate
  ok "Generated from project.yml"
  note "Re-run 'xcodegen generate' (or this script) after editing project.yml."
}

resolve_packages() {
  if [[ $SKIP_RESOLVE -eq 1 ]]; then
    step "Skipping package resolution (--skip-resolve)"
    note "Xcode will resolve the packages the first time you open the project."
    return 0
  fi

  step "Resolving Swift packages"
  info "Downloading Mapbox, Supabase and the Spotify SDK — a cold cache takes a few minutes."
  if ! xcodebuild -resolvePackageDependencies -project "$XCODEPROJ"; then
    printf '\n'
    warn "Package resolution failed."
    info "If the failure mentions a 403 or api.mapbox.com, the downloads token in ~/.netrc is"
    info "missing, expired, or lacks the DOWNLOADS:READ scope. Verify it with:"
    info "  curl -s -o /dev/null -w '%{http_code}\\n' -n \\"
    info "    https://api.mapbox.com/downloads/v2/mapbox-common/releases/ios/packages/24.27.0/MapboxCommon.zip"
    info "A 200 means the credential works; 401/403 means it doesn't."
    exit 1
  fi
  ok "Packages resolved"
}

# ----------------------------------------------------------------- finish ----

summary() {
  step "Setup complete"

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '    %sFollow up on:%s\n' "$YELLOW" "$RESET"
    local w
    for w in "${WARNINGS[@]}"; do
      printf '      • %s\n' "$w"
    done
    printf '\n'
  fi

  info "Next:"
  info "  open $XCODEPROJ"
  info "  xcodebuild -project $XCODEPROJ -scheme Kaido \\"
  info "    -destination \"platform=iOS Simulator,name=iPhone 17\" test"
  printf '\n'
  note "Secrets live in $SECRETS_FILE (gitignored). Re-run with --reconfigure to change them."

  if [[ $OPEN_XCODE -eq 1 ]]; then
    open "$XCODEPROJ"
  fi
}

check_prerequisites
configure_secrets
configure_mapbox_downloads
generate_project
resolve_packages
summary
