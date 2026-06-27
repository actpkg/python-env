# sqlite3 is built into the wasm CPython (both lean and sci builds). An in-memory
# database needs NO capabilities — in-process SQL alongside the Python namespace.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import sqlite3\ncon = sqlite3.connect(':memory:')\ncon.execute('create table t(n int, s text)')\ncon.executemany('insert into t values (?,?)', [(1,'a'),(2,'b'),(3,'c')])\ncon.execute('select count(*), sum(n) from t where n > 1').fetchone()"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "(2, 5)"
