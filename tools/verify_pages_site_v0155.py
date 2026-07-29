#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.pages-site').resolve()
project = Path(__file__).resolve().parent.parent
raise SystemExit(subprocess.run([sys.executable, str(project / 'tools/verify_pages_site_v0155_fix1.py'), str(root)], cwd=project).returncode)
