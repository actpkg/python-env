async def test_msgpack_round_trips_a_nested_structure(client, exec_meta):
    # Scientific tier: msgpack — fast C++ binary serialization. Requires the
    # sci build (`just build sci`). Pack a nested structure and round-trip it.
    code = (
        "import msgpack\n"
        "obj = {'a': [1, 2, 3], 'b': {'x': 3.5, 'y': True}, 'c': b'bytes'}\n"
        "back = msgpack.unpackb(msgpack.packb(obj), raw=False)\n"
        'f"ver={msgpack.version} ok={back == obj}"'
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    text = result.content[0].text
    assert "ok=True" in text
    assert "ver=(1, 2, 1)" in text
