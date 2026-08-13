async def test_state_persists_across_calls_in_one_session(client, exec_meta):
    # A variable defined in one call, a function in another, and both used in
    # a third — the point of the test is that all three calls see the same
    # namespace (the session), not just that the last one returns the right
    # value. A raised exception on any of the three fails the test, so the
    # first two calls succeeding is verified implicitly.
    await client.call_tool("exec", {"code": "counter = 100", "_meta": exec_meta})
    await client.call_tool(
        "exec",
        {
            "code": "def bump():\n    global counter\n    counter += 1\n    return counter",
            "_meta": exec_meta,
        },
    )
    result = await client.call_tool(
        "exec", {"code": "bump(); bump(); counter", "_meta": exec_meta}
    )
    assert result.content[0].text == "102"
