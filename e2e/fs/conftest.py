"""Overrides `client` with a `wasi:filesystem` grant, for the test in this
directory that has `exec` write and read back a data file. Everything else
(`session`, `exec_meta`, `expect_error`, `act_command`, `wasm_path`) is
inherited unchanged from the parent `conftest.py` — fixtures that depend on
`client` resolve to this override automatically for tests under `fs/`.
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
    """An MCP client granted the component's full declared `wasi:filesystem`
    ceiling (`**`, rw) — same shape as the old justfile's `test-fs` recipe
    (`--allow wasi:filesystem`). The test itself is self-contained via
    `tempfile`, so it needs no particular path scoped in, just the grant to
    exist at all.
    """
    transport = StdioTransport(
        command=act_command[0],
        args=[
            *act_command[1:],
            "run",
            str(wasm_path),
            "--mcp",
            "--allow",
            "wasi:filesystem",
        ],
        keep_alive=False,
        log_file=LOG_FILE,
    )
    async with Client(transport) as connected:
        yield connected
