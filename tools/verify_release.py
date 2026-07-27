"""Compatibility entry point for the V0.14.2 authoritative verifier."""
from pathlib import Path
import runpy, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
target=Path(__file__).with_name('verify_release_v0142.py')
sys.argv=[str(target),str(root)]
runpy.run_path(str(target),run_name='__main__')
