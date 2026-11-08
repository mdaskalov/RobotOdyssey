"""Puts Apple2Kit's Data/ on the import path: the tools this folder shares
with it (dis6502.py, hexdump.py, hires.py) live there.  The package:
$APPLE2KIT_PACKAGE, else ../../Apple2Kit beside this project."""
import os
import sys

_root = os.environ.get("APPLE2KIT_PACKAGE") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Apple2Kit")
sys.path.append(os.path.join(_root, "Data"))
