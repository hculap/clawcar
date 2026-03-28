#!/usr/bin/env bash
# scripts/dhu-test.sh — Launch Android Auto Desktop Head Unit (DHU) for testing.
#
# Prerequisites:
#   1. Android SDK installed with ANDROID_HOME set
#   2. DHU installed via SDK Manager (SDK Tools > Android Auto Desktop Head Unit Emulator)
#   3. Phone/emulator running with ClawCar app installed
#   4. ADB connected to the device
#
# Usage:
#   ./scripts/dhu-test.sh            # Start DHU (default: TCP on port 5277)
#   ./scripts/dhu-test.sh --usb      # Start DHU over USB transport

set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
DHU_PATH="${ANDROID_HOME}/extras/google/auto/desktop-head-unit"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[DHU]${NC} $*"; }
warn()  { echo -e "${YELLOW}[DHU]${NC} $*"; }
error() { echo -e "${RED}[DHU]${NC} $*" >&2; }

# ── Verify prerequisites ────────────────────────────────────────────

if ! command -v adb &>/dev/null; then
  error "adb not found. Install Android SDK Platform Tools."
  exit 1
fi

if [[ ! -f "${DHU_PATH}" ]]; then
  error "DHU not found at ${DHU_PATH}"
  echo ""
  echo "Install it via Android Studio SDK Manager:"
  echo "  SDK Tools tab → check 'Android Auto Desktop Head Unit Emulator'"
  echo ""
  echo "Or via command line:"
  echo "  sdkmanager 'extras;google;auto'"
  exit 1
fi

# ── Check device / emulator connectivity ────────────────────────────

DEVICES=()
while IFS= read -r line; do
  serial="${line%%[[:space:]]*}"
  [[ -n "${serial}" ]] && DEVICES+=("${serial}")
done < <(adb devices | grep 'device$')

if [[ ${#DEVICES[@]} -eq 0 ]]; then
  error "No device connected. Connect a phone or start an emulator."
  exit 1
fi

ADB_SERIAL=""
if [[ ${#DEVICES[@]} -gt 1 ]]; then
  warn "Multiple devices detected:"
  for i in "${!DEVICES[@]}"; do
    echo "  [$((i+1))] ${DEVICES[$i]}"
  done
  echo ""
  read -rp "Select device [1-${#DEVICES[@]}]: " choice
  if [[ "${choice}" -ge 1 && "${choice}" -le ${#DEVICES[@]} ]] 2>/dev/null; then
    ADB_SERIAL="${DEVICES[$((choice-1))]}"
  else
    error "Invalid selection."
    exit 1
  fi
else
  ADB_SERIAL="${DEVICES[0]}"
fi

ADB=(adb -s "${ADB_SERIAL}")
info "Using device: ${ADB_SERIAL}"

# ── Determine transport ─────────────────────────────────────────────

TRANSPORT="tcp"
if [[ "${1:-}" == "--usb" ]]; then
  TRANSPORT="usb"
fi

# ── Set up TCP port forwarding (for TCP transport) ──────────────────

if [[ "${TRANSPORT}" == "tcp" ]]; then
  info "Setting up ADB port forwarding (tcp:5277 → tcp:5277)..."
  "${ADB[@]}" forward tcp:5277 tcp:5277
fi

# ── Enable Android Auto developer mode on device ────────────────────

info "Enabling Android Auto developer mode on device..."
"${ADB[@]}" shell am start -a com.google.android.projection.gearhead.DEVELOPER_SETTINGS 2>/dev/null || true

warn "If this is your first time:"
echo "  1. Open Android Auto on your phone"
echo "  2. Tap version number 10x to enable Developer Mode"
echo "  3. Open Developer Settings → Enable 'Unknown sources'"
echo ""

# ── Launch DHU ──────────────────────────────────────────────────────

info "Launching DHU (transport: ${TRANSPORT})..."
echo ""
echo "──────────────────────────────────────────────────"
echo "  ClawCar should appear on the DHU screen."
echo "  Tap the ClawCar icon → tap the mic button."
echo "──────────────────────────────────────────────────"
echo ""

exec "${DHU_PATH}" --transport="${TRANSPORT}"
