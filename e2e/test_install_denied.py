async def test_install_denied_without_a_grant(client):
    # Capability gate: without a wasi:http grant, install is denied (no
    # network egress happens — the host policy blocks the request).
    # Hermetic. `install` is not session-bound, so no `exec_meta` needed.
    result = await client.call_tool("install", {"package": "six"})
    assert "install failed" in result.content[0].text
