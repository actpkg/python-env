async def test_sqlite3_in_memory_database_needs_no_capability(client, exec_meta):
    # sqlite3 is built into the wasm CPython (both lean and sci builds). An
    # in-memory database needs NO capabilities — in-process SQL alongside the
    # Python namespace.
    code = (
        "import sqlite3\n"
        "con = sqlite3.connect(':memory:')\n"
        "con.execute('create table t(n int, s text)')\n"
        "con.executemany('insert into t values (?,?)', [(1,'a'),(2,'b'),(3,'c')])\n"
        "con.execute('select count(*), sum(n) from t where n > 1').fetchone()"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "(2, 5)"
