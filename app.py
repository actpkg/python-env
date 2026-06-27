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

from act_sdk import component, session_close, session_open, tool
from act_sdk.bridge import SessionProvider, ToolProvider  # noqa: F401 — componentize-py entry points


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
