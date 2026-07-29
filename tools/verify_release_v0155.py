#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
raise SystemExit(subprocess.run([sys.executable, 'tools/verify_release_v0155_fix1.py', '.'], cwd=root).returncode)
