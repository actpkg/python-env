# Filesystem access: exec writes and reads back a data file. Requires a
# wasi:filesystem grant (run the server with --allow wasi:filesystem); without a
# grant, file ops raise PermissionError. Self-contained via tempfile.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import tempfile, csv, os\nfd, p = tempfile.mkstemp(suffix='.csv')\nos.close(fd)\nopen(p, 'w').write('x,y\\n1,2\\n3,4\\n')\nrows = list(csv.reader(open(p)))\nos.remove(p)\nf'rows={len(rows)} last={rows[-1]}'"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "rows=3"
jsonpath "$.content[0].data" contains "last=['3', '4']"
