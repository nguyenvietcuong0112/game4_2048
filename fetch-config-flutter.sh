#!/bin/bash
set -e

# ============================================================================
#  fetch-config-flutter.sh -- Keo config bundle tu server Funtap ve project tren macOS.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS="$SCRIPT_DIR/fetch-config-flutter.js"
URL="https://fgtool.funtapglobal.com"

if ! command -v node &> /dev/null; then
    echo "[fetch] LOI: khong tim thay 'node'. Hay cai Node.js truoc."
    exit 1
fi

if [ ! -f "$JS" ]; then
    echo "[fetch] LOI: khong thay fetch-config-flutter.js o root project."
    exit 1
fi

FORCE=""
if [ "$1" == "force" ]; then
    FORCE="--force"
fi

echo ""
read -p "[fetch] Nhap API Key (Enter de dung key da luu): " APIKEY

if [ -n "$APIKEY" ]; then
    node "$JS" --key "$APIKEY" --url "$URL" --project "$SCRIPT_DIR" $FORCE
else
    node "$JS" --url "$URL" --project "$SCRIPT_DIR" $FORCE
fi

echo ""
echo "============================================================================"
echo " [!] Config da ghi vao android/app/src/main/assets + ios/Runner."
echo " [!] Chay tiep:  flutter pub get  roi  flutter run"
echo "============================================================================"
echo ""
