#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / '.pages-site'
raise SystemExit(subprocess.run([sys.executable, str(root / 'tools/prepare_pages_site_v0155_fix1.py'), str(root), str(out)], cwd=root).returncode)
