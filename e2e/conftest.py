"""Shared fixtures for the MCP-driven e2e suite.

The suite drives the packed component through `act run --mcp` over stdio with
a real MCP client, so what the tests observe is what an agent observes.

python-env is a session-provider: every `exec`/`reset_session` call needs
`std:session-id` in its argument metadata (ACT-MCP §3.2) — `EnvSession` is
the per-session persistent namespace. This suite gets that id by calling the
virtual `open_session`/`close_session` tools the MCP adapter synthesises for
any session-provider component — the path an agent actually uses — rather
than starting the host with `--session-args` (session-of-1), which the old
justfile's hurl recipes did. That shortcut opens the session *before* the
host's listener comes up, so a guest that stalls in `open-session` leaves a
host that never comes up with nothing on stderr; see `sqlite`'s conftest for
the same reasoning. `install` is the one tool that is NOT session-bound
(measured: `app.py`'s `install()` takes no `session` parameter, and a probe
against the packed wasm confirms it answers with no session open at all), so
tests that only call `install` don't need the `session`/`exec_meta` fixtures.

Subdirectories override `client` to add the grant their suite needs
(`net/conftest.py` adds `wasi:http`, `fs/conftest.py` adds `wasi:filesystem`);
`sci/` needs no grant, same as this directory. Fixtures defined here that
build on `client` (`session`, `exec_meta`) resolve whichever `client` is
closest to the test being run, so they work unchanged in every subdirectory.
"""

import json
import os
import shlex
import subprocess
import pytest
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

# Measured in docs/specs/2026-08-08-e2e-harness-findings.md, question 1.
from mcp.shared.exceptions import McpError

WASM = "python-env.wasm"

# ACT's audit trail writes to stderr unconditionally — it is not governed by
# RUST_LOG — so it is redirected to a file rather than left to flood pytest.
LOG_FILE = Path(".pytest-act-stderr.log")


@pytest.fixture(scope="session")
def act_command() -> list[str]:
    """The ACT invocation, honouring the same override the justfile uses.

    Parsed with shlex, not treated as a single path: the justfile's own
    default for its `act` variable is `npx @actcore/act` — two words — which
    cannot be `argv[0]` for a non-shell `subprocess.run`/`StdioTransport`
    call. A bare `os.environ.get("ACT", "act")` string breaks that default;
    splitting it is what makes both forms ("act" on PATH, and the npx
    two-word default) actually spawn.
    """
    return shlex.split(os.environ.get("ACT", "act"))


@pytest.fixture(scope="session")
def wasm_path(act_command: list[str]) -> Path:
    """The packed component.

    Existence is not enough and neither is a fresh mtime: `just build` (lean)
    or `just build-sci` alone can leave a stale wasm behind if interrupted,
    and an unpacked artifact declares no capability ceiling, so every grant
    is refused as "outside ceiling" and the failures point anywhere but here.
    This has already bitten repeatedly in this workspace, so the fixture
    checks the section rather than the file.

    One `wasm_path` for the whole suite, lean or sci: the justfile rebuilds
    `python-env.wasm` in place per variant (`test`/`test-net` run against
    whatever was last built — lean in CI; `test-fs`/`test-sci` rebuild it as
    sci first), so the test files never need to know which tier produced it.
    """
    path = Path(WASM)
    if not path.exists():
        pytest.fail(f"{path} is missing — run `just build` (or `just build sci`) first")
    probe = subprocess.run(
        [*act_command, "inspect", "component-manifest", str(path)],
        capture_output=True,
        text=True,
    )
    name = json.loads(probe.stdout or "{}").get("std", {}).get("name", "unknown")
    if name in ("", "unknown"):
        pytest.fail(f"{path} is built but not packed — run `just build` again")
    return path


@pytest.fixture
async def client(act_command: list[str], wasm_path: Path):
    """An ungranted MCP client, one `act` process per test.

    No grant: every hermetic-suite assertion (this directory and `sci/`) is
    reachable without one — `install-denied.hurl`'s whole point is that
    `install` fails cleanly with no `wasi:http` grant, and `exec`'s stdlib
    surface (including `sqlite3`, an in-memory database) needs no capability
    at all. `net/` and `fs/` override this fixture with the grant their
    suite needs.

    Measured spawn+connect cost on the lean (47 MB) build: ~0.92s per fresh
    process (3-run average, `list_tools`/`open_session` themselves add only a
    few ms on top). That is the dominant per-test cost here, unlike the much
    smaller components in this workspace (~250ms measured elsewhere), but the
    full suite is small enough (order of 30 test functions across all four
    directories) that a fresh process per test stays under a minute even at
    that rate — so this stays function-scoped, the same safe default as
    every other component's suite, rather than widening to share a process
    (and therefore share session/namespace state) across tests.
    """
    transport = StdioTransport(
        command=act_command[0],
        args=[*act_command[1:], "run", str(wasm_path), "--mcp"],
        keep_alive=False,
        log_file=LOG_FILE,
    )
    async with Client(transport) as connected:
        yield connected


@pytest.fixture
async def session(client) -> str:
    """A per-test session, opened via the virtual `open_session` tool (it
    takes no arguments — `EnvSession.__init__` takes none) and closed via
    `close_session` after the test.
    """
    opened = await client.call_tool("open_session", {})
    sid = json.loads(opened.content[0].text)["id"]
    yield sid
    await client.call_tool("close_session", {"session_id": sid})


@pytest.fixture
def exec_meta(session: str) -> dict:
    """The `_meta` argument-channel payload `exec`/`reset_session` need.
    `std:session-id` keeps its `std:` spelling here — the argument channel
    (ACT-MCP §3.2) is deliberately exempt from the `dev.actcore/` respelling
    that governs MCP's transport-level `_meta` field (§3.1); writing
    `dev.actcore/session-id` in this channel would not be recognised.
    """
    return {"std:session-id": session}


@pytest.fixture
def expect_error():
    """Assert a call fails with a specific ACT error kind.

    Exposed as a fixture rather than a plain function so tests never have to
    import from `conftest` — that import only resolves when the test
    directory happens to be on `sys.path`, which is not something to rely on.

    Measured, not assumed. `call-tool` in `act:tools` returns a bare
    `tool-result` with NO `result<>` wrapper — only `list-tools` has one — so
    a guest reporting a failed tool call can only do it through
    `tool-event::error`, which arrives as a result with `is_error` set and the
    kind in `_meta`. **That is the path a tool test will take.**

    The JSON-RPC error path exists for failures that are not the guest's tool
    body: `list-tools`, the session operations, a wasmtime trap, an
    unreachable actor. It raises `mcp.shared.exceptions.McpError` with the
    payload at `exc.error.data`. No tool test in this suite is expected to
    reach it — `install` reports a failed install as text in its result
    rather than as an ACT error (see `app.py`) — but both are handled here
    so callers need not care.
    """

    async def _expect(client, tool: str, arguments: dict, kind: str):
        try:
            result = await client.call_tool(tool, arguments, raise_on_error=False)
        except McpError as exc:
            data = getattr(getattr(exc, "error", None), "data", None) or {}
            assert data.get("dev.actcore/error-kind") == kind, (
                f"expected {kind} on the JSON-RPC error path, got {data!r}"
            )
            return

        assert result.is_error, f"expected {tool} to fail, got {result!r}"
        meta = result.meta or {}
        assert meta.get("dev.actcore/error-kind") == kind, (
            f"expected {kind} on the isError path, got {meta!r}"
        )

    return _expect
