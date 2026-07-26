"""Compatibility entry point. V0.13.1 authoritative verifier is verify_release_v0131.py."""
from pathlib import Path
import runpy, sys
script=Path(__file__).with_name('verify_release_v0131.py')
sys.argv=[str(script),*(sys.argv[1:] or ['.'])]
runpy.run_path(str(script),run_name='__main__')
