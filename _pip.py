"""Runtime pure-Python wheel installer for python-env (Phase 2).

Fetches pure-`*-none-any` wheels from PyPI over wasi:http (p3) and serves them
from an in-memory importlib finder. Installs are process-global (shared across
sessions); per-session exec namespaces remain isolated.
"""

import importlib
import importlib.abc
import importlib.util
import io
import sys
import types
import zipfile

# zipfile decodes non-UTF8-flagged entry names with cp437; that codec is lazily
# imported and not frozen by componentize-py unless referenced — freeze it.
import encodings.cp437  # noqa: F401

# micropip.PackageManager.install calls site.getsitepackages(); stub it (we never
# touch disk — install() routes wheels into the in-memory finder).
try:
    import site

    site.getsitepackages = lambda *a, **k: ["/session-packages"]  # type: ignore[attr-defined]
except Exception:  # noqa: BLE001
    _m = types.ModuleType("site")
    _m.getsitepackages = lambda *a, **k: ["/session-packages"]  # type: ignore[attr-defined]
    sys.modules["site"] = _m

import micropip._utils as _mp_utils
from micropip._compat import CompatibilityNotInPyodide
from micropip._vendored.packaging.src.packaging.tags import Tag as _Tag
from micropip.package_manager import PackageManager

import wit_world
from componentize_py_types import Ok
from wit_world.imports import client
from wit_world.imports.wasi_http_types import Fields, Request, Response, Scheme_Https


# micropip._utils.sys_tags() calls sysconfig.get_config_var(), which imports the
# missing _sysconfigdata__wasi_wasm32-wasi module and crashes in-guest. Replace
# it with a pure-Python-only tag set: fixes the crash AND enforces pure-wheels-
# only (any cp3x/abi3/platform wheel is now incompatible → resolver skips it).
def _pure_sys_tags() -> tuple:
    major, minor = sys.version_info[0], sys.version_info[1]
    tags = [_Tag(f"py{major}{minor}", "none", "any"), _Tag(f"py{major}", "none", "any")]
    tags += [_Tag(f"py{major}{m}", "none", "any") for m in range(minor - 1, -1, -1)]
    return tuple(tags)


# Version-locked to micropip 0.11.1 (pinned in pyproject): this reaches into
# micropip internals (_utils.sys_tags call-site, _vendored.packaging layout).
# Re-verify the sys_tags shape and CompatibilityLayer methods on any bump.
_mp_utils.sys_tags = _pure_sys_tags


def _split_url(url: str) -> tuple[str, str]:
    if not url.startswith("https://"):
        raise ValueError(f"only https supported: {url}")
    rest = url[len("https://") :].split("#", 1)[0]
    slash = rest.find("/")
    return (rest, "/") if slash == -1 else (rest[:slash], rest[slash:])


async def _http_get(
    url: str, req_headers: dict | None = None
) -> tuple[int, dict, bytes]:
    fields = Fields()
    for k, v in (req_headers or {}).items():
        fields.append(k, v.encode() if isinstance(v, str) else bytes(v))
    trailers = wit_world.result_option_wasi_http_types_fields_wasi_http_types_error_code_future(
        lambda: Ok(None)
    )[1]
    authority, path = _split_url(url)
    request, _sent = Request.new(fields, None, trailers, None)
    request.set_scheme(Scheme_Https())
    request.set_authority(authority)
    request.set_path_with_query(path)

    response = await client.send(request)
    status = response.get_status_code()
    headers = {
        name.lower(): bytes(value).decode("latin-1")
        for name, value in response.get_headers().copy_all()
    }
    res_fut = wit_world.result_unit_wasi_http_types_error_code_future(lambda: Ok(None))[
        1
    ]
    rx, _trailers = Response.consume_body(response, res_fut)
    buf = bytearray()
    with rx:
        while not rx.writer_dropped:
            buf.extend(await rx.read(65536))
    return status, headers, bytes(buf)


class _InMemoryFinder(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    def __init__(self) -> None:
        self._modules: dict[str, tuple[bytes, bool, str]] = {}

    def add_wheel(self, buffer: bytes, filename: str) -> None:
        if not filename.endswith("-none-any.whl"):
            raise ValueError(f"refusing non-pure wheel: {filename}")
        with zipfile.ZipFile(io.BytesIO(buffer)) as zf:
            for name in zf.namelist():
                if (
                    not name.endswith(".py")
                    or ".dist-info/" in name
                    or ".data/" in name
                ):
                    continue
                mod = name[:-3].replace("/", ".")
                if mod == "__init__":
                    continue
                if mod.endswith(".__init__"):
                    fullname, is_pkg = mod[: -len(".__init__")], True
                else:
                    fullname, is_pkg = mod, False
                self._modules[fullname] = (
                    zf.read(name),
                    is_pkg,
                    f"<wheel:{filename}>/{name}",
                )
        importlib.invalidate_caches()

    def find_spec(self, fullname, path=None, target=None):
        if fullname not in self._modules:
            return None
        _src, is_pkg, origin = self._modules[fullname]
        return importlib.util.spec_from_loader(
            fullname, self, origin=origin, is_package=is_pkg
        )

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        src, is_pkg, origin = self._modules[module.__name__]
        if is_pkg:
            module.__path__ = []
        exec(compile(src, origin, "exec"), module.__dict__)


_FINDER = _InMemoryFinder()
if _FINDER not in sys.meta_path:
    sys.meta_path.append(_FINDER)


class _WasiHttpCompat(CompatibilityNotInPyodide):
    @staticmethod
    async def fetch_bytes(url: str, kwargs: dict) -> bytes:
        status, _h, body = await _http_get(url, kwargs.get("headers"))
        if status >= 400:
            raise OSError(f"HTTP {status} for {url}")
        return body

    @staticmethod
    async def fetch_string_and_headers(url: str, kwargs: dict) -> tuple[str, dict]:
        status, headers, body = await _http_get(url, kwargs.get("headers"))
        if status >= 400:
            raise OSError(f"HTTP {status} for {url}")
        return body.decode("utf-8"), headers

    @staticmethod
    async def install(buffer, filename, install_dir, metadata=None):
        _FINDER.add_wheel(bytes(buffer), filename)


async def install(package: str, index_url: str | None = None) -> None:
    """Install a pure-Python package (and its pure deps); raises on failure.

    `index_url` overrides the package index (a PEP 503/691 "simple" index). Use it
    to target a curated / private / air-gapped index instead of PyPI. The index
    host must still be reachable under the `wasi:http` egress grant — restrict that
    grant to your index host to *force* all installs through it (hardened supply
    chain enforced by ACT's capability model, not by trusting the caller).
    """
    pm = PackageManager(_WasiHttpCompat)
    kwargs = {"index_urls": [index_url]} if index_url else {}
    await pm.install(package, **kwargs)
