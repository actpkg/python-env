# Scientific tier: msgpack — fast C++ binary serialization. Requires the sci
# build (`just build-sci`). Pack a nested structure and round-trip it.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import msgpack\nobj = {'a': [1, 2, 3], 'b': {'x': 3.5, 'y': True}, 'c': b'bytes'}\nback = msgpack.unpackb(msgpack.packb(obj), raw=False)\nf\"ver={msgpack.version} ok={back == obj}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "ok=True"
jsonpath "$.content[0].data" contains "ver=(1, 2, 1)"
