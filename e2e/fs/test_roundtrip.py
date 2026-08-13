async def test_exec_writes_and_reads_back_a_data_file(client, exec_meta):
    # Filesystem access: exec writes and reads back a data file. Requires a
    # wasi:filesystem grant; without one, file ops raise PermissionError.
    # Self-contained via tempfile.
    code = (
        "import tempfile, csv, os\n"
        "fd, p = tempfile.mkstemp(suffix='.csv')\n"
        "os.close(fd)\n"
        "open(p, 'w').write('x,y\\n1,2\\n3,4\\n')\n"
        "rows = list(csv.reader(open(p)))\n"
        "os.remove(p)\n"
        "f'rows={len(rows)} last={rows[-1]}'"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    text = result.content[0].text
    assert "rows=3" in text
    assert "last=['3', '4']" in text
