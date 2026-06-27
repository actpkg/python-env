# Capability gate: without a wasi:http grant, install is denied (no network
# egress happens — the host policy blocks the request). Hermetic.
POST {{baseurl}}/tools/install
{"arguments": {"package": "six"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "install failed"
