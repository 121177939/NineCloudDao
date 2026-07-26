"""Compatibility entry point. V0.14.0 authoritative verifier is verify_release_v0140.py."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('verify_release_v0140.py')), run_name='__main__')
