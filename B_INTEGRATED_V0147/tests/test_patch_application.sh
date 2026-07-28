#!/usr/bin/env bash
set -euo pipefail
MODULE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE_ROOT="${1:-/mnt/data/ncd_v0146_ab4_review}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$BASELINE_ROOT/app.js" "$TMP/app.js"
cp "$BASELINE_ROOT/styles.css" "$TMP/styles.css"
patch -s -d "$TMP" -p1 < "$MODULE_ROOT/patches/app.js.patch"
patch -s -d "$TMP" -p1 < "$MODULE_ROOT/patches/styles.css.patch"
cmp -s "$TMP/app.js" "$MODULE_ROOT/source/candidate/app.js"
cmp -s "$TMP/styles.css" "$MODULE_ROOT/source/candidate/styles.css"
node --check "$TMP/app.js"
echo 'PASS patches apply cleanly and match candidate files'
