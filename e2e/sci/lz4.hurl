# Scientific tier: lz4 — fast compression. Requires the sci build (`just
# build-sci`). Round-trip + verify it actually compresses repetitive data.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import lz4.frame as f\ndata = b'hello world ' * 100\nc = f.compress(data)\n(f.decompress(c) == data, len(c) < len(data))"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "(True, True)"
