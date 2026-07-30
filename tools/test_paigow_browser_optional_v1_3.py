#!/usr/bin/env python3
"""Optional local browser test. Never used by the production Pages workflow."""
from pathlib import Path
import importlib.util, shutil, subprocess, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
chromium=shutil.which('chromium') or shutil.which('chromium-browser') or shutil.which('google-chrome')
if importlib.util.find_spec('playwright') is None or not chromium:
    print('SKIP optional browser test: Playwright or Chromium is unavailable')
    raise SystemExit(0)
legacy=root/'tools/test_paigow_stable_ui_cache40.py'
if chromium != '/usr/bin/chromium':
    print(f'SKIP optional legacy browser test: discovered browser is {chromium}, legacy test expects /usr/bin/chromium')
    raise SystemExit(0)
subprocess.run([sys.executable,str(legacy),str(root)],cwd=root,check=True)
