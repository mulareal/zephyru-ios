#!/usr/bin/env bash
# Applies the ZephyrU iOS port on top of a pinned upstream Cemu checkout.
#
# Usage: scripts/apply_port.sh [cemu_dir] [--sha <commit>]
#
# The result is a Cemu source tree with:
#   - patches/0001-zephyru-cemu-core.patch applied
#   - ios/ overlaid (platform layer + UIKit app)
#   - required submodules initialized
set -euo pipefail

CEMU_SHA_DEFAULT="3310f3b8b184d64a62b89fd59088c799432badf5"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CEMU_DIR="${1:-$ROOT_DIR/cemu}"
CEMU_SHA="${2:-$CEMU_SHA_DEFAULT}"

if [ ! -d "$CEMU_DIR/.git" ]; then
	echo "[zephyru] cloning Cemu @ $CEMU_SHA into $CEMU_DIR"
	git init "$CEMU_DIR" >/dev/null
	git -C "$CEMU_DIR" remote add origin https://github.com/cemu-project/Cemu.git
	git -C "$CEMU_DIR" fetch --depth 1 origin "$CEMU_SHA"
	git -C "$CEMU_DIR" checkout -q FETCH_HEAD
fi

echo "[zephyru] checking out $CEMU_SHA"
git -C "$CEMU_DIR" checkout -q "$CEMU_SHA" 2>/dev/null || {
	git -C "$CEMU_DIR" fetch --depth 1 origin "$CEMU_SHA"
	git -C "$CEMU_DIR" checkout -q FETCH_HEAD
}

echo "[zephyru] applying core patch"
git -C "$CEMU_DIR" apply --whitespace=nowarn "$ROOT_DIR/patches/0001-zephyru-cemu-core.patch"

echo "[zephyru] overlaying ios/"
rm -rf "$CEMU_DIR/ios"
cp -R "$ROOT_DIR/ios" "$CEMU_DIR/ios"

echo "[zephyru] initializing submodules"
git -C "$CEMU_DIR" submodule update --init --depth 1 \
	dependencies/xbyak_aarch64 \
	dependencies/metal-cpp \
	dependencies/imgui \
	dependencies/ZArchive

echo "[zephyru] port applied to $CEMU_DIR"
