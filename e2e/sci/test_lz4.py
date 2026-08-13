async def test_lz4_round_trip_and_compresses(client, exec_meta):
    # Scientific tier: lz4 — fast compression. Requires the sci build (`just
    # build sci`). Round-trip + verify it actually compresses repetitive data.
    code = (
        "import lz4.frame as f\n"
        "data = b'hello world ' * 100\n"
        "c = f.compress(data)\n"
        "(f.decompress(c) == data, len(c) < len(data))"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "(True, True)"
