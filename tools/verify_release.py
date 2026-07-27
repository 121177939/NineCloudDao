"""Compatibility entry point for the V0.14.3 authoritative verifier."""
from pathlib import Path
import runpy

target=Path(__file__).with_name('verify_release_v0143.py')
runpy.run_path(str(target),run_name='__main__')
