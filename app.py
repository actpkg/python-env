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
from act_sdk import Content, Multi, component, session_close, session_open, tool
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
# >>> sci-imports (generated from pyproject [tool.python-env.freeze] — do not edit by hand)
try:
    import numpy  # noqa: F401
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
    import pandas  # noqa: F401
    # pandas lazily imports its display formatters on first use; freeze them so
    # DataFrame repr / to_string / to_html / to_csv / info work offline (else
    # ModuleNotFoundError: 'pandas.io.formats.string' on a DataFrame repr).
    import pandas.io.formats.string  # noqa: F401 — DataFrame __repr__ / to_string
    import pandas.io.formats.html  # noqa: F401 — to_html / notebook repr
    import pandas.io.formats.console  # noqa: F401
    import pandas.io.formats.format  # noqa: F401
    import pandas.io.formats.printing  # noqa: F401
    import pandas.io.formats.info  # noqa: F401 — df.info()
    import pandas.io.formats.csvs  # noqa: F401 — to_csv
except ImportError:
    pass
try:
    import regex  # noqa: F401
except ImportError:
    pass
try:
    import PIL.Image  # noqa: F401
    import PIL.ImageFile  # noqa: F401
    import PIL.ImageFont  # noqa: F401
    import PIL.PngImagePlugin  # noqa: F401
    import PIL.JpegImagePlugin  # noqa: F401
    import PIL.BmpImagePlugin  # noqa: F401
    import PIL.GifImagePlugin  # noqa: F401
    import PIL.PpmImagePlugin  # noqa: F401
    import PIL.ImageDraw  # noqa: F401
    import PIL.ImageOps  # noqa: F401
    import PIL.ImageFilter  # noqa: F401
    import PIL.ImageColor  # noqa: F401
    import PIL.ImageChops  # noqa: F401
    import PIL.ImageEnhance  # noqa: F401
    import PIL.ImageStat  # noqa: F401
    import PIL.ImageMath  # noqa: F401
except ImportError:
    pass
try:
    import msgpack  # noqa: F401
except ImportError:
    pass
try:
    import lxml.etree  # noqa: F401
    import lxml.html  # noqa: F401
except ImportError:
    pass
try:
    import lz4.frame  # noqa: F401
except ImportError:
    pass
try:
    import bottleneck  # noqa: F401
except ImportError:
    pass
# <<< sci-imports


class EnvSession:
    """Per-session persistent state: the namespace `exec` runs against."""

    def __init__(self) -> None:
        self.globals: dict = {"__builtins__": __builtins__}


# Leading bytes → MIME, so `show(img_bytes)` can name the part without the
# caller passing a mime. Anything unrecognised is opaque octet-stream.
_MAGIC: list[tuple[bytes, str]] = [
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"GIF87a", "image/gif"),
    (b"GIF89a", "image/gif"),
    (b"%PDF-", "application/pdf"),
    (b"<svg", "image/svg+xml"),
]


def _sniff_mime(data: bytes) -> str:
    for magic, mime in _MAGIC:
        if data.startswith(magic):
            return mime
    return "application/octet-stream"


def _make_show(parts: list):
    """`show(data, mime=None)` — emit an extra content part from an exec call.

    Lets `exec` return real binary output (e.g. a PNG from Pillow) alongside the
    text result. `data` may be bytes (mime sniffed if omitted) or str.
    """

    def show(data, mime: str | None = None) -> None:
        if isinstance(data, str):
            parts.append(Content(mime or "text/plain", data.encode("utf-8")))
        elif isinstance(data, (bytes, bytearray)):
            b = bytes(data)
            parts.append(Content(mime or _sniff_mime(b), b))
        else:
            raise TypeError("show() expects bytes or str")

    return show


def _run(code: str, ns: dict) -> object:
    """Execute *code* against *ns*, returning the result.

    Returns the text representation (stdout + last-expression repr + errors). If
    the code called ``show(...)`` to emit binary/image parts, returns a ``Multi``
    of the text followed by those parts instead.

    Uses the IPython-style "last expression" heuristic: if the last top-level
    statement is a bare expression, eval it to capture its repr; exec the
    preceding statements first so side-effects (assignments, imports) land in
    the namespace before the expression is evaluated.
    """
    content_parts: list = []
    ns["show"] = _make_show(content_parts)
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
    text = "\n".join(parts) if parts else "(no output)"
    if content_parts:
        # text first (only if there was any), then the emitted binary parts.
        return Multi(*([text] if parts else []), *content_parts)
    return text


@component
class PythonEnv:
    @session_open
    def open(self) -> EnvSession:
        return EnvSession()

    @session_close
    def close(self, session: EnvSession) -> None:
        session.globals.clear()

    @tool(
        description=(
            "Execute Python against this session's persistent namespace. Call "
            "show(data, mime=None) to return binary/image output (e.g. a PNG "
            "from Pillow) alongside the text result."
        )
    )
    async def exec(self, code: str, *, session: EnvSession) -> object:
        return _run(code, session.globals)

    @tool(description="Clear all variables/imports in this session's namespace")
    async def reset_session(self, *, session: EnvSession) -> str:
        session.globals.clear()
        session.globals["__builtins__"] = __builtins__
        return "(session reset)"

    @tool(
        description=(
            "Install a pure-Python package (shared across all sessions). Optional "
            "index_url targets a curated/private index instead of PyPI."
        )
    )
    async def install(self, package: str, index_url: str | None = None) -> str:
        try:
            await _pip.install(package, index_url=index_url)
        except Exception as exc:  # noqa: BLE001
            return f"install failed: {exc}"
        where = index_url or "PyPI"
        return f"installed {package} from {where} (importable in any session via exec)"
