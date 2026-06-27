"""ACT component: stateful, batteries-included Python environment.

Each act:sessions session is a persistent Python namespace: variables,
imports, and definitions survive across `exec` calls within the session;
separate sessions are fully isolated. Sessions are required — use
``--session-args '{}'`` (or ``--session-args '{"key": val}'``) to open one.
"""

import ast
import io
import sys
import traceback

import _wasi_compat  # noqa: F401 — inject ctypes stub etc. BEFORE anything imports them
from act_sdk import component, session_close, session_open, tool
from act_sdk.bridge import SessionProvider, ToolProvider  # noqa: F401 — componentize-py entry points
import _freeze_stdlib  # noqa: F401 — freezes the full stdlib so `install`ed pkgs work
import _pip

# Pre-import bundled batteries so componentize-py freezes them into the wasm.
import attr as _attr  # noqa: F401
import bs4 as _bs4  # noqa: F401
import dateutil as _dateutil  # noqa: F401
import jinja2 as _jinja2  # noqa: F401
import markdown as _markdown  # noqa: F401
import more_itertools as _more_itertools  # noqa: F401
import mpmath as _mpmath  # noqa: F401
import rich as _rich  # noqa: F401
import slugify as _slugify  # noqa: F401
import sortedcontainers as _sortedcontainers  # noqa: F401
import tabulate as _tabulate  # noqa: F401
import yaml as _yaml  # noqa: F401

# Scientific tier: numpy + pandas are supplied on the componentize-py
# --python-path by the `just build-sci` recipe (the patched wasm-EH toolchain) and
# get folded/frozen here. In the lean `just build` (stock toolchain) they are
# absent, so each is skipped and the component is unchanged.
try:
    import numpy as _numpy  # noqa: F401

    # numpy lazy-loads these submodules via numpy.__getattr__; componentize-py only
    # freezes statically-reached modules, so import them here for pandas to use.
    import numpy.char  # noqa: F401
    import numpy.fft  # noqa: F401
    import numpy.lib  # noqa: F401
    import numpy.linalg  # noqa: F401
    import numpy.ma  # noqa: F401
    import numpy.polynomial  # noqa: F401
    import numpy.rec  # noqa: F401
    import numpy.strings  # noqa: F401
except ImportError:
    pass
try:
    import pandas as _pandas  # noqa: F401
except ImportError:
    pass


class EnvSession:
    """Per-session persistent state: the namespace `exec` runs against."""

    def __init__(self) -> None:
        self.globals: dict = {"__builtins__": __builtins__}


def _run(code: str, ns: dict) -> str:
    """Execute *code* against *ns*, returning a text representation of the result.

    Uses the IPython-style "last expression" heuristic: if the last top-level
    statement is a bare expression, eval it to capture its repr; exec the
    preceding statements first so side-effects (assignments, imports) land in
    the namespace before the expression is evaluated.
    """
    old_out, old_err = sys.stdout, sys.stderr
    cap_out, cap_err = io.StringIO(), io.StringIO()
    sys.stdout, sys.stderr = cap_out, cap_err
    result_value = None
    error_text = None
    try:
        try:
            result_value = eval(compile(code, "<act>", "eval"), ns)
        except SyntaxError:
            tree = ast.parse(code, mode="exec")
            if tree.body and isinstance(tree.body[-1], ast.Expr):
                last = tree.body.pop()
                if tree.body:
                    exec(compile(tree, "<act>", "exec"), ns)
                expr = ast.Expression(body=last.value)
                ast.fix_missing_locations(expr)
                result_value = eval(compile(expr, "<act>", "eval"), ns)
            else:
                exec(compile(code, "<act>", "exec"), ns)
    except Exception:
        error_text = traceback.format_exc()
    finally:
        sys.stdout, sys.stderr = old_out, old_err
    parts = []
    out = cap_out.getvalue()
    err = cap_err.getvalue()
    if out:
        parts.append(out)
    if result_value is not None:
        parts.append(repr(result_value))
    if err:
        parts.append(f"[stderr]\n{err}")
    if error_text:
        parts.append(f"[error]\n{error_text}")
    return "\n".join(parts) if parts else "(no output)"


@component
class PythonEnv:
    @session_open
    def open(self) -> EnvSession:
        return EnvSession()

    @session_close
    def close(self, session: EnvSession) -> None:
        session.globals.clear()

    @tool(description="Execute Python against this session's persistent namespace")
    async def exec(self, code: str, *, session: EnvSession) -> str:
        return _run(code, session.globals)

    @tool(description="Clear all variables/imports in this session's namespace")
    async def reset_session(self, *, session: EnvSession) -> str:
        session.globals.clear()
        session.globals["__builtins__"] = __builtins__
        return "(session reset)"

    @tool(description="Install a pure-Python package from PyPI (shared across all sessions)")
    async def install(self, package: str) -> str:
        try:
            await _pip.install(package)
        except Exception as exc:  # noqa: BLE001
            return f"install failed: {exc}"
        return f"installed {package} (importable in any session via exec)"
