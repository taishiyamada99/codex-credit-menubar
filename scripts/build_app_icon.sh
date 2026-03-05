#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ICNS="${1:-${ROOT_DIR}/output/AppIcon.icns}"
WORK_DIR="$(mktemp -d)"
BASE_PNG="${WORK_DIR}/AppIcon-1024.png"
ICONSET_DIR="${WORK_DIR}/AppIcon.iconset"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

swift "${ROOT_DIR}/scripts/generate_icon.swift" "${BASE_PNG}" >/dev/null

mkdir -p "${ICONSET_DIR}"

make_size() {
  local size="$1"
  local file="$2"
  sips -z "${size}" "${size}" "${BASE_PNG}" --out "${ICONSET_DIR}/${file}" >/dev/null
}

make_size 16 icon_16x16.png
make_size 32 icon_16x16@2x.png
make_size 32 icon_32x32.png
make_size 64 icon_32x32@2x.png
make_size 128 icon_128x128.png
make_size 256 icon_128x128@2x.png
make_size 256 icon_256x256.png
make_size 512 icon_256x256@2x.png
make_size 512 icon_512x512.png
make_size 1024 icon_512x512@2x.png

mkdir -p "$(dirname "${OUTPUT_ICNS}")"
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"

echo "Generated icon: ${OUTPUT_ICNS}"
