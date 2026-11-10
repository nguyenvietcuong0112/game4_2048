#!/bin/bash
set -e

# ============================================================================
#  build-info-flutter.sh -- Sinh file BUILD INFO canh thu muc build tren macOS / Linux.
#
#  CHAY SAU KHI BUILD:  flutter build apk   (hoac flutter build ipa / build ios)
#  Dat o ROOT project Flutter (ngang pubspec.yaml).
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS="$SCRIPT_DIR/funtap_global_sdk/tools/fg-build-info.js"

if [ ! -f "$SCRIPT_DIR/pubspec.yaml" ]; then
    echo "[build-info] LOI: khong thay pubspec.yaml -- dat file o ROOT project Flutter."
    exit 2
fi

if [ ! -f "$JS" ]; then
    echo "[build-info] LOI: khong thay funtap_global_sdk/tools/fg-build-info.js"
    exit 2
fi

if ! command -v node &> /dev/null; then
    echo "[build-info] LOI: chua cai Node.js."
    exit 2
fi

PKGVER=$(grep -E "^version:" "$SCRIPT_DIR/funtap_global_sdk/pubspec.yaml" | head -n 1 | awk '{print $2}')

node "$JS" --project "$SCRIPT_DIR" --engine flutter --platform android --pkg-version "funtap-global-sdk-flutter $PKGVER"
node "$JS" --project "$SCRIPT_DIR" --engine flutter --platform ios     --pkg-version "funtap-global-sdk-flutter $PKGVER"

echo ""
echo "[build-info] XONG. Mo file .txt trong thu muc build de soat truoc khi nop ban build."
