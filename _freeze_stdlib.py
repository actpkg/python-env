"""Freeze the full CPython stdlib into the component at build time.

componentize-py only bundles modules that are imported during its build-time
pre-init. Our app reaches only a slice of the stdlib, so runtime-`install`ed
packages that import an unreached stdlib module (e.g. sympy → `timeit`) fail at
import. Importing every stdlib module here pulls the whole stdlib into the
snapshot, so the installer works for the broad pure-Python ecosystem.

Modules that can't load under WASI CPython (no `_ctypes`/`mmap`/`_ssl`/…) raise
and are skipped — that's expected and harmless. A few are skipped outright
because importing them has side effects or hangs.
"""

import importlib
import pkgutil
import sys

# Skip: side effects on import, GUI/dev-only, or known to hang under pre-init.
_SKIP = frozenset(
    {
        "antigravity",
        "this",
        "__hello__",
        "__phello__",
        "idlelib",
        "turtle",
        "turtledemo",
        "tkinter",
        "test",
        "lib2to3",
        "pydoc_data",
        "ensurepip",
        "venv",
        "__main__",
    }
)


def _try(name):
    try:
        return importlib.import_module(name)
    except BaseException:  # noqa: BLE001 — WASI-absent C-exts raise; skip them
        return None


for _name in sorted(sys.stdlib_module_names):
    if _name in _SKIP or _name.startswith(("_test", "test")):
        continue
    _mod = _try(_name)
    # For packages, also pull in every submodule (e.g. importlib.resources,
    # concurrent.futures, the codecs under encodings, json/urllib/email/xml…)
    # so installed packages that import them don't hit a freeze gap.
    if _mod is not None and hasattr(_mod, "__path__"):
        try:
            for _info in pkgutil.walk_packages(_mod.__path__, _name + ".", onerror=lambda _n: None):
                _try(_info.name)
        except BaseException:  # noqa: BLE001
            pass
