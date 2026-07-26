"""Compatibility entry point for the V0.14.1 authoritative verifier."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('verify_release_v0141.py')),run_name='__main__')
