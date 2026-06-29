"""
Minimal smoke test component.
Imports sqlite3 (a CPython C-extension) to prove the toolchain can fold C-exts.
"""

import sqlite3
import wit_world


class WitWorld(wit_world.WitWorld):
    def sqlite_version(self) -> str:
        return sqlite3.sqlite_version
