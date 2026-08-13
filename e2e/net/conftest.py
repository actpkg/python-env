"""Overrides `client` with a `wasi:http` grant, for the tests in this
directory that call `install` against the real PyPI. Everything else
(`session`, `exec_meta`, `expect_error`, `act_command`, `wasm_path`) is
inherited unchanged from the parent `conftest.py` — fixtures that depend on
`client` resolve to this override automatically for tests under `net/`.
"""

import pytest
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

# Mirrors the parent conftest.py's constant. Not imported from it — `from
# conftest import ...` only resolves when the test directory happens to be on
# sys.path, which is not something to rely on (same reasoning as the
# `expect_error` fixture across this workspace's suites).
LOG_FILE = Path(".pytest-act-stderr.log")


@pytest.fixture
async def client(act_command: list[str], wasm_path: Path):
    """An MCP client granted the component's full declared `wasi:http`
    ceiling (`pypi.org` + `files.pythonhosted.org`) — same shape as the old
    justfile's `test-net` recipe (`--allow wasi:http`). These tests make
    real HTTPS requests; they need outbound network from wherever they run.
    """
    transport = StdioTransport(
        command=act_command[0],
        args=[*act_command[1:], "run", str(wasm_path), "--mcp", "--allow", "wasi:http"],
        keep_alive=False,
        log_file=LOG_FILE,
    )
    async with Client(transport) as connected:
        yield connected
