async def test_regex_fuzzy_matching(client, exec_meta):
    # Scientific tier: the `regex` C extension (faster/extended `re`).
    # Requires the sci build (`just build sci`). Exercises features stdlib
    # `re` lacks: fuzzy (approximate) matching and Unicode property classes.
    code = "import regex; regex.search('(?:colour){e<=1}', 'my color here').group()"
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "'color'"


async def test_regex_unicode_property_classes(client, exec_meta):
    code = "import regex; regex.findall('\\\\p{Lu}', 'Hello World ABC')"
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "['H', 'W', 'A', 'B', 'C']"
