#!/usr/bin/env python3
from pathlib import Path
import runpy, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
sys.argv=[str(Path(__file__).with_name('sql_static_audit_v0141_fix7a.py')),str(root)]
runpy.run_path(sys.argv[0],run_name='__main__')
