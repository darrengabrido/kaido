#!/usr/bin/env bash
#
# Build, install, and launch Kaido on a connected physical iPhone.
#
#   scripts/run_on_device.sh [--release] [--device <name-or-udid>]
#
# Requires scripts/setup.sh to have been run already (DEVELOPMENT_TEAM set in
# Config/Secrets.xcconfig — signed builds fail without it) and the iPhone
# unlocked, connected (cable or Wi-Fi debugging), and trusted for this Mac.
#
# With one device connected, no --device is needed. With more than one,
# pass --device (or set $KAIDO_DEVICE) with a name/UDID substring, or the
# script lists what it found and asks you to pick.

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

XCODEPROJ="Kaido.xcodeproj"
SCHEME="Kaido"
BUNDLE_ID="com.oaktreehouse.kaido"
CONFIGURATION="Debug"
DERIVED_DATA="DerivedData/device"
DEVICE_MATCH="${KAIDO_DEVICE:-}"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; RESET=""
fi

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
info() { printf '    %s\n' "$1"; }
ok()   { printf '    %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Build, install, and launch Kaido on a connected physical iPhone.

Usage: scripts/run_on_device.sh [options]

Options:
  --release          Build the Release configuration (default: Debug).
  --device <match>   Name or UDID substring picking which connected device
                      to use. Also settable via $KAIDO_DEVICE.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)  CONFIGURATION="Release" ;;
    --device)   shift; DEVICE_MATCH="${1:-}" ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

[[ -d "$XCODEPROJ" ]] || die "$XCODEPROJ not found — run scripts/setup.sh first."

# ------------------------------------------------------------- find device --

step "Looking for a connected device"

# xcodebuild's own destination list is the most reliable source of "what can
# I actually build for" — it already accounts for the SDKs Xcode has
# installed. Physical devices report as "platform:iOS,"; simulators report as
# "platform:iOS Simulator,", so matching the comma right after iOS excludes them.
raw_destinations="$(xcodebuild -showdestinations -project "$XCODEPROJ" -scheme "$SCHEME" 2>/dev/null \
  | grep -E '^[[:space:]]*\{ platform:iOS,' || true)"

[[ -n "$raw_destinations" ]] || die "No physical device found.
       Plug in an iPhone (or enable Wi-Fi debugging), unlock it, and tap
       \"Trust This Computer\" if prompted, then try again."

UDIDS=()
NAMES=()
while IFS= read -r line; do
  udid="$(sed -E 's/.*id:([A-Za-z0-9-]+).*/\1/' <<<"$line")"
  name="$(sed -E 's/.*name:([^}]*)\}.*/\1/; s/[[:space:]]+$//' <<<"$line")"
  UDIDS+=("$udid")
  NAMES+=("$name")
done <<<"$raw_destinations"

MATCH_IDX=()
if [[ -n "$DEVICE_MATCH" ]]; then
  for i in "${!UDIDS[@]}"; do
    if [[ "${NAMES[$i]}" == *"$DEVICE_MATCH"* || "${UDIDS[$i]}" == *"$DEVICE_MATCH"* ]]; then
      MATCH_IDX+=("$i")
    fi
  done
  [[ ${#MATCH_IDX[@]} -gt 0 ]] || die "No connected device matches '$DEVICE_MATCH'."
else
  for i in "${!UDIDS[@]}"; do MATCH_IDX+=("$i"); done
fi

if [[ ${#MATCH_IDX[@]} -eq 1 ]]; then
  SELECTED=${MATCH_IDX[0]}
elif [[ -t 0 ]]; then
  info "Multiple devices matched:"
  for n in "${!MATCH_IDX[@]}"; do
    i=${MATCH_IDX[$n]}
    printf '      %d) %s (%s)\n' "$((n + 1))" "${NAMES[$i]}" "${UDIDS[$i]}"
  done
  read -r -p "    Pick one [1-${#MATCH_IDX[@]}]: " choice
  [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#MATCH_IDX[@]} ]] ||
    die "Invalid choice."
  SELECTED=${MATCH_IDX[$((choice - 1))]}
else
  die "Multiple devices connected — pass --device <name-or-udid> (or set \$KAIDO_DEVICE) to pick one:
$(for i in "${MATCH_IDX[@]}"; do printf '       - %s (%s)\n' "${NAMES[$i]}" "${UDIDS[$i]}"; done)"
fi

UDID="${UDIDS[$SELECTED]}"
DEVICE_NAME="${NAMES[$SELECTED]}"
ok "$DEVICE_NAME ($UDID)"

# ------------------------------------------------------------------- build --

step "Building ($CONFIGURATION)"
xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/Kaido.app"
[[ -d "$APP_PATH" ]] || die "Build succeeded but $APP_PATH is missing."
ok "Built $APP_PATH"

# --------------------------------------------------------- install + launch --

step "Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$UDID" "$APP_PATH"
ok "Installed"

step "Launching Kaido"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
ok "Kaido is running on $DEVICE_NAME"
