#!/usr/bin/env bash
set -euo pipefail
MODULE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE_ROOT="${1:-/mnt/data/ncd_v0146_ab4_review}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

python "$MODULE_ROOT/tests/sql_static_audit.py"
node "$MODULE_ROOT/tests/test_technique_book_ui.js" "$MODULE_ROOT"
"$MODULE_ROOT/tests/test_patch_application.sh" "$BASELINE_ROOT"
node --check "$MODULE_ROOT/source/candidate/app.js"

cp -a "$BASELINE_ROOT/." "$STAGE/"
cp "$MODULE_ROOT/source/candidate/app.js" "$STAGE/app.js"
cp "$MODULE_ROOT/source/candidate/styles.css" "$STAGE/styles.css"
node "$STAGE/tools/test_features_v0145.js" "$STAGE"
node "$STAGE/tools/test_opportunity_history_v0146.js" "$STAGE"
node "$STAGE/tools/test_casino_render_v0141.js" "$STAGE"
node "$STAGE/tools/test_world_events_render_v0142.js" "$STAGE"
node "$STAGE/tools/test_ranking_render_v0143.js" "$STAGE"
python "$STAGE/tools/sql_static_audit_v0146.py" "$STAGE"
echo 'ALL SELECTED STATIC TESTS PASSED'
