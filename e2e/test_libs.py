async def test_all_bundled_pure_python_libraries_import_in_one_session(
    client, exec_meta
):
    # Smoke test: all 12 bundled pure-Python libraries can be imported in one session.
    code = (
        "import jinja2, markdown, bs4, rich, tabulate, slugify, yaml, dateutil, "
        "attr, more_itertools, sortedcontainers, mpmath\nprint('all imported')"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert "all imported" in result.content[0].text
