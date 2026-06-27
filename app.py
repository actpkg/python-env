"""ACT component: stateful, batteries-included Python environment.

Each act:sessions session is a persistent Python namespace: variables,
imports, and definitions survive across `exec` calls within the session;
separate sessions are isolated. A call with no session runs in a throwaway
namespace (stateless fallback).
"""

import ast
import contextvars
import io
import sys
import traceback

from act_sdk import component, tool, session_open, session_close

# Current session for this tool dispatch; set by CustomToolProvider before
# calling dispatch_tool so the tools can access it without a `*, session` param.
# This enables the optional-session pattern: scoped when std:session-id is
# present, throwaway namespace when absent.
_env_session: contextvars.ContextVar = contextvars.ContextVar("env_session", default=None)


class EnvSession:
    """Per-session persistent state: the namespace `exec` runs against."""

    def __init__(self) -> None:
        self.globals: dict = {"__builtins__": __builtins__}


def _run(code: str, ns: dict) -> str:
    """Execute *code* against *ns*, returning a text representation of the result.

    Uses the IPython-style "last expression" heuristic: if the last statement is
    a bare expression, eval it to capture its repr; exec the preceding statements
    first.
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
    async def exec(self, code: str) -> str:
        session = _env_session.get()
        ns = session.globals if session is not None else {"__builtins__": __builtins__}
        return _run(code, ns)

    @tool(description="Clear all variables/imports in this session's namespace")
    async def reset_session(self) -> str:
        session = _env_session.get()
        if session is None:
            return "(no session)"
        session.globals.clear()
        session.globals["__builtins__"] = __builtins__
        return "(session reset)"


# Override ToolProvider with one that sets _env_session before dispatch.
# This gives tools optional session access without requiring std:session-id.
# The guard handles host-side imports (wit_world only exists in the WASM guest).
try:
    from act_sdk.bridge import ToolProvider as _SDKToolProvider
    from act_sdk.bridge import SessionProvider  # noqa: F401
    from act_sdk.provider import _sessions as _sdk_sessions
    from act_sdk.sessions import session_id_from_metadata

    class ToolProvider(_SDKToolProvider):
        """Extends SDK ToolProvider to inject session via contextvar."""

        async def call_tool(self, name, arguments, metadata):
            sid = session_id_from_metadata(list(metadata))
            session = _sdk_sessions.get(sid) if sid is not None else None
            token = _env_session.set(session)
            try:
                return await super().call_tool(name, arguments, metadata)
            finally:
                _env_session.reset(token)

except ImportError:
    pass
