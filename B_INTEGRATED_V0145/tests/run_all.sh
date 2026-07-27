#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node --check "$ROOT/source/candidate/app.js"
node "$ROOT/tests/test_combined_ui.js"
node "$ROOT/tests/test_opportunity_v4_ui.js" "$ROOT/source/candidate/app.js" "$ROOT/source/candidate/styles.css"
python "$ROOT/tests/sql_static_audit.py"
python "$ROOT/tests/test_probability_math.py"
python "$ROOT/tests/test_commission_math.py"
node "$ROOT/tests/test_player_house_commission_ui.js"
echo "ALL STATIC TESTS PASSED"
