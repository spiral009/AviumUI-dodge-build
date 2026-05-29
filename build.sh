#!/usr/bin/env bash
# =============================================================================
# AviumUI OnePlus 13 (dodge) - Build & Package Script
# =============================================================================
# Produces a single all-in-one OrangeFox-flashable ZIP using the AOSP Edify
# updater (installer/META-INF/com/google/android/update-binary). Edify reads the
# zip with libziparchive (ZIP64 / >4GB-safe), so the big super.img lives inside
# the zip and there is NO busybox unzip and NO payload.bin (OFOX can't apply
# payload.bin). The updater-script flashes boot-class images to BOTH slots and
# extracts super.img -> simg2img -> /dev/block/by-name/super. This mirrors the
# known-good AviumUI flashable zips for this device.
#
# FLASH: OrangeFox > Install > the ZIP > swipe > reboot.  (One file, all-in-one.)
#
# Usage:  ./build.sh [userdebug|user|eng] [--clean] [--package-only]
# Requirements: synced Android source, ~250GB free disk, 16GB+ RAM.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

DEVICE="dodge"
RELEASE="bp4a"
JOBS=$(nproc)
BUILD_TYPE="userdebug"
CLEAN_BUILD=false
PACKAGE_ONLY=false
PRODUCT_OUT="out/target/product/${DEVICE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${SCRIPT_DIR}/installer"        # committed Edify update-binary + updater-script

for arg in "$@"; do
    case "$arg" in
        --clean|-c)         CLEAN_BUILD=true ;;
        --package-only|-p)  PACKAGE_ONLY=true ;;
        userdebug|user|eng) BUILD_TYPE="$arg" ;;
    esac
done
LUNCH_TARGET="lineage_${DEVICE}-${RELEASE}-${BUILD_TYPE}"

echo -e "${BLUE}=== AviumUI build: ${LUNCH_TARGET} (jobs ${JOBS}, clean ${CLEAN_BUILD}, pkgonly ${PACKAGE_ONLY}) ===${NC}"

echo -e "${YELLOW}[1/7] Env...${NC}"
[[ -f build/envsetup.sh ]] || { echo -e "${RED}Not in Android source root.${NC}"; exit 1; }
[[ -f "${INSTALLER_DIR}/META-INF/com/google/android/update-binary" ]] || {
    echo -e "${RED}Missing ${INSTALLER_DIR}/META-INF/.../update-binary (Edify updater).${NC}"; exit 1; }
FREE_GB=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
[[ "$FREE_GB" -ge 50 ]] || { echo -e "${RED}Need >=50GB free, found ${FREE_GB}GB.${NC}"; exit 1; }

echo -e "${YELLOW}[2/7] envsetup...${NC}"
source build/envsetup.sh
mk() {  # robust: prefer `m` function, else soong_ui (non-login shells)
    if [ "$(type -t m 2>/dev/null)" = "function" ]; then m -j"${JOBS}" "$@"
    else build/soong/soong_ui.bash --make-mode TARGET_RELEASE="${RELEASE}" "$@"; fi
}

echo -e "${YELLOW}[3/7] lunch ${LUNCH_TARGET}...${NC}"
lunch "${LUNCH_TARGET}"; export TARGET_RELEASE="${RELEASE}"
echo -e "${GREEN}TARGET_PRODUCT=${TARGET_PRODUCT:-?} RELEASE=${TARGET_RELEASE}${NC}"

if [[ "$CLEAN_BUILD" == true && "$PACKAGE_ONLY" == false ]]; then
    echo -e "${YELLOW}[3.5/7] Clean...${NC}"; mk clean
fi

if [[ "$PACKAGE_ONLY" == false ]]; then
    echo -e "${YELLOW}[4/7] Building ROM (bacon)...${NC}"; mk bacon
else
    echo -e "${YELLOW}[4/7] --package-only: skip build${NC}"
fi

echo -e "${YELLOW}[5/7] Building super.img...${NC}"
mk superimage
[[ -f "${PRODUCT_OUT}/super.img" ]] || { echo -e "${RED}super.img not found${NC}"; exit 1; }

echo -e "${YELLOW}[6/7] Staging images + Edify installer...${NC}"
STAGING_DIR=$(mktemp -d); trap 'rm -rf "${STAGING_DIR}"' EXIT
for img in boot.img init_boot.img dtbo.img vendor_boot.img vbmeta.img vbmeta_system.img vbmeta_vendor.img super.img; do
    [[ -f "${PRODUCT_OUT}/${img}" ]] && cp "${PRODUCT_OUT}/${img}" "${STAGING_DIR}/${img}" \
        || echo -e "${YELLOW}  missing (non-fatal): ${img}${NC}"
done
cp -a "${INSTALLER_DIR}/META-INF" "${STAGING_DIR}/META-INF"
chmod +x "${STAGING_DIR}/META-INF/com/google/android/update-binary"

echo -e "${YELLOW}[7/7] Packaging all-in-one ZIP...${NC}"
DATE=$(date +%Y%m%d)
ZIP_NAME="AviumUI-dodge-${DATE}-${BUILD_TYPE}-OFOX.zip"
OUTPUT_ZIP="${PWD}/${ZIP_NAME}"
rm -f "$OUTPUT_ZIP"
( cd "$STAGING_DIR" && zip -r1 "$OUTPUT_ZIP" . )

echo ""
echo -e "${GREEN}=== Build complete ===${NC}"
echo -e "${GREEN}Flashable (all-in-one):${NC} ${OUTPUT_ZIP}  ($(du -h "$OUTPUT_ZIP" | cut -f1))"
echo -e "${YELLOW}Flash:${NC} OrangeFox > Install > that zip > swipe > reboot to System."
