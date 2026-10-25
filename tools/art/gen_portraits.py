"""Portraits, 96x96 (SPEC-art-audio): one module per character under tools/art/portraits/.

Week 5 ships Wren; the rest of the cast lands in weeks 6 and 9.

    python tools/art/gen_portraits.py [id ...]      (no id = every portrait)
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/portraits")
SIZE = 96
PORTRAITS: tuple[str, ...] = ("wren",)


def draw(portrait_id: str):
    return importlib.import_module(f"portraits.{portrait_id}").draw()


def build(root: Path, ids: tuple[str, ...] | None = None) -> None:
    for portrait_id in ids or PORTRAITS:
        draw(portrait_id).save(Path(root) / OUT_DIR / f"{portrait_id}.png")


if __name__ == "__main__":
    build(REPO_ROOT, tuple(sys.argv[1:]) or None)
    print("portraits:", ", ".join(sys.argv[1:] or PORTRAITS))
