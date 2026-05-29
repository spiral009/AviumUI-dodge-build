#!/usr/bin/env bash
# =============================================================================
# AviumUI OnePlus 13 (dodge) - Build Script
# =============================================================================
# Produces the standard all-in-one A/B OTA zip (payload.bin) via `bacon`.
#
# This is the PROPER flashable package for an A/B + dynamic-partition device:
# OrangeFox/TWRP apply it natively with update_engine (libziparchive, ZIP64/
# >4GB-safe) — no busybox unzip, no super.img surgery, no custom installer.
#
# FLASH (either works):
#   * OrangeFox > Install > AviumUI-*-GMS.zip   (OFOX detects payload.bin)
#   * OrangeFox > Advanced > ADB Sideload, then on PC:
#       adb sideload AviumUI-*-GMS.zip
#   It writes to the inactive slot and switches; reboot to System.
#
# Usage:  ./build.sh [userdebug|user|eng] [--clean]
# Requirements: synced Android source, ~250GB free disk, 16GB+ RAM.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

DEVICE="dodge"
RELEASE="bp4a"                       # A16 release config for this tree
JOBS=$(nproc)
BUILD_TYPE="userdebug"
CLEAN_BUILD=false
PRODUCT_OUT="out/target/product/${DEVICE}"

for arg in "$@"; do
    case "$arg" in
        --clean|-c)         CLEAN_BUILD=true ;;
        userdebug|user|eng) BUILD_TYPE="$arg" ;;
    esac
done
LUNCH_TARGET="lineage_${DEVICE}-${RELEASE}-${BUILD_TYPE}"

echo -e "${BLUE}=== AviumUI build: ${LUNCH_TARGET} (jobs ${JOBS}, clean ${CLEAN_BUILD}) ===${NC}"

echo -e "${YELLOW}[1/5] Env...${NC}"
[[ -f build/envsetup.sh ]] || { echo -e "${RED}Not in Android source root.${NC}"; exit 1; }
FREE_GB=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
[[ "$FREE_GB" -ge 50 ]] || { echo -e "${RED}Need >=50GB free, found ${FREE_GB}GB.${NC}"; exit 1; }

echo -e "${YELLOW}[2/5] envsetup...${NC}"
source build/envsetup.sh
# Robust make wrapper: prefer the `m` function, else soong_ui (works in
# non-interactive / CI shells where `m` may be shadowed by a stray binary).
mk() {
    if [ "$(type -t m 2>/dev/null)" = "function" ]; then m -j"${JOBS}" "$@"
    else build/soong/soong_ui.bash --make-mode TARGET_RELEASE="${RELEASE}" "$@"; fi
}

echo -e "${YELLOW}[3/5] lunch ${LUNCH_TARGET}...${NC}"
lunch "${LUNCH_TARGET}"
export TARGET_RELEASE="${RELEASE}"
echo -e "${GREEN}TARGET_PRODUCT=${TARGET_PRODUCT:-?} RELEASE=${TARGET_RELEASE}${NC}"

if [[ "$CLEAN_BUILD" == true ]]; then
    echo -e "${YELLOW}[3.5/5] Clean...${NC}"; mk clean
fi

echo -e "${YELLOW}[4/5] Building OTA (bacon) — this takes a while...${NC}"
mk bacon

echo -e "${YELLOW}[5/5] Locating OTA zip...${NC}"
OTA=$(ls -t "${PRODUCT_OUT}"/AviumUI-*-GMS.zip "${PRODUCT_OUT}"/lineage-*.zip "${PRODUCT_OUT}"/*-ota.zip 2>/dev/null | head -1 || true)
[[ -n "${OTA:-}" && -f "$OTA" ]] || { echo -e "${RED}OTA zip not found in ${PRODUCT_OUT}${NC}"; exit 1; }

echo ""
echo -e "${GREEN}=== Build complete ===${NC}"
echo -e "${GREEN}Flashable A/B OTA:${NC} ${OTA}  ($(du -h "$OTA" | cut -f1))"
echo ""
echo -e "${YELLOW}Flash:${NC} OrangeFox > Install > that zip   (OR  Advanced > ADB Sideload"
echo -e "       then 'adb sideload <zip>').  It applies payload.bin natively and"
echo -e "       switches slots — reboot to System when done."
