"""install: fetch a pure-Python wheel from PyPI at runtime.

NOTE: every test in this file makes real HTTPS requests to pypi.org and
files.pythonhosted.org; it requires outbound network from wherever it runs.
"""

import re


async def test_install_then_import_in_the_default_session(client, exec_meta):
    # Install a tiny pure-Python package at runtime, then import it in the
    # session. Installs are process-global, so a session opened in the same
    # process — any session — sees it.
    installed = await client.call_tool("install", {"package": "six"})
    assert "installed six" in installed.content[0].text

    # six is now importable.
    imported = await client.call_tool(
        "exec", {"code": "import six; six.__version__", "_meta": exec_meta}
    )
    assert re.search(r"^'\d+\.\d+", imported.content[0].text)

    # A stdlib-heavy pure-Python package: sympy imports `timeit` (full-stdlib
    # freeze) and `ctypes` (WASI-absent → stub). Proves `install` works
    # beyond trivial wheels.
    installed_sympy = await client.call_tool("install", {"package": "sympy"})
    assert "installed sympy" in installed_sympy.content[0].text

    factored = await client.call_tool(
        "exec", {"code": "import sympy; str(sympy.factorint(360))", "_meta": exec_meta}
    )
    assert factored.content[0].text == "'{2: 3, 3: 2, 5: 1}'"

    # index_url targets a specific index (here PyPI explicitly). A deployment
    # pins a curated/private index here AND restricts the wasi:http egress
    # allowlist to its host, so installs are confined to it by the
    # capability model.
    installed_toolz = await client.call_tool(
        "install", {"package": "toolz", "index_url": "https://pypi.org/simple"}
    )
    assert (
        "installed toolz from https://pypi.org/simple"
        in installed_toolz.content[0].text
    )

    # `_pip` (the install tool's own implementation module) is importable
    # from `exec` code, and app.py's exec harness supports a top-level
    # `await` — same PyCF_ALLOW_TOP_LEVEL_AWAIT pattern CPython's own asyncio
    # REPL and Pyodide's console use — so `await _pip.install(...)` runs for
    # real from a single exec call, no separate install-tool round-trip needed.
    code = (
        'import _pip\nawait _pip.install("humanize")\nimport humanize\n'
        "humanize.naturalsize(1234567)"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "'1.2 MB'"
