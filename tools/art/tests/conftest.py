"""Puts tools/art on sys.path so tests import the pipeline modules the way
build_all.py does when run as a script."""

import sys
from pathlib import Path

ART_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = ART_DIR.parents[1]

if str(ART_DIR) not in sys.path:
    sys.path.insert(0, str(ART_DIR))
