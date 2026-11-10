#!/bin/bash
set -e

# ============================================================================
#  install-fgsdk-flutter.sh -- Cai / Update FGSDK vao project Flutter tren macOS.
#
#  CACH DUNG:
#    - Cach 1: Chay trong Terminal: ./install-fgsdk-flutter.sh
#    - Cach 2: Double-click file install-fgsdk-flutter.command trong Finder
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="funtap-global-sdk-flutter"
DARTPKG="funtap_global_sdk"
REGISTRY="https://packages.funtapglobal.com/"
TMP="$SCRIPT_DIR/.fgsdk-flutter-tmp"
PKGDIR="$TMP/package"
DEST="$SCRIPT_DIR/$DARTPKG"

echo ""
echo "[FGSDK-FL] Project root : $SCRIPT_DIR"
echo "[FGSDK-FL] Package      : $PKG (keo ban MOI NHAT tu registry)"
echo ""

if [ ! -f "$SCRIPT_DIR/pubspec.yaml" ]; then
    echo "[FGSDK-FL] LOI: khong thay 'pubspec.yaml' -- script phai nam o ROOT project Flutter."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo "[FGSDK-FL] LOI: khong tim thay 'npm'. Hay cai Node.js truoc."
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "[FGSDK-FL] LOI: khong tim thay 'node'. Hay cai Node.js truoc."
    exit 1
fi

echo "[FGSDK-FL] [1/4] Tai pack tu registry..."
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"

npm pack "$PKG" --registry="$REGISTRY"

TGZ=$(ls -t ${PKG}-*.tgz 2>/dev/null | head -n 1)
if [ -z "$TGZ" ]; then
    echo "[FGSDK-FL] LOI: khong thay file .tgz sau khi pack."
    rm -rf "$TMP"
    exit 1
fi

echo "        -> Da tai xong: $TGZ"

echo "[FGSDK-FL] [2/4] Giai nen -> $DARTPKG/ ..."
tar -xzf "$TGZ"
cd "$SCRIPT_DIR"

rm -rf "$DEST"
mv "$PKGDIR" "$DEST"
rm -rf "$TMP"

# Match Dart SDK environment constraint for this project
sed -i '' 's/sdk: \^3\.13\.2/sdk: ">=3.13.0 <4.0.0"/g' "$DEST/pubspec.yaml" 2>/dev/null || true

# Ensure FGBridge cleans up pending completers when native is unavailable
node -e '
var f = "'"$DEST"'/lib/src/fg_bridge.dart";
var fs = require("fs");
var s = fs.readFileSync(f, "utf8");
if (!s.includes("_cbMap.values")) {
  s = s.replace("_unavailable = true;", "_unavailable = true;\n    for (final c in _cbMap.values) { if (!c.isCompleted) c.complete(null); }\n    _cbMap.clear();");
  fs.writeFileSync(f, s);
}
' 2>/dev/null || true

echo "[FGSDK-FL] [3/4] Rai script tool -> ROOT project ..."
cp -f "$DEST/tools/fetch-config-flutter.js" "$SCRIPT_DIR/fetch-config-flutter.js"
if [ -f "$DEST/tools/fetch-config-flutter.bat" ]; then
    cp -f "$DEST/tools/fetch-config-flutter.bat" "$SCRIPT_DIR/fetch-config-flutter.bat"
fi

echo "[FGSDK-FL] [4/4] Dau day pubspec.yaml + minSdk..."
node "$DEST/tools/wire-flutter.js" --project "$SCRIPT_DIR"

echo ""
echo "============================================================================"
echo "[FGSDK-FL] HOAN TAT! SDK da duoc cap nhat vao $DARTPKG/"
echo "Cac buoc tiep theo:"
echo "  1. flutter pub get"
echo "  2. flutter run"
echo "============================================================================"
echo ""
