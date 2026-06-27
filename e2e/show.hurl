# exec can emit binary/image content via show(), returned as extra content parts
# alongside the text result. Hermetic (raw bytes, no Pillow) — the mime is sniffed
# from the leading bytes (PNG magic here).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "show(b'\\x89PNG\\r\\n\\x1a\\nFAKE'); 'img made'"}}
HTTP 200
[Asserts]
jsonpath "$.content" count == 2
jsonpath "$.content[0].mime_type" == "text/plain"
jsonpath "$.content[0].data" contains "img made"
jsonpath "$.content[1].mime_type" == "image/png"
jsonpath "$.content[1].data" == "iVBORw0KGgpGQUtF"

# An explicit mime overrides sniffing.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "show(b'hello', 'application/octet-stream'); None"}}
HTTP 200
[Asserts]
jsonpath "$.content" count == 1
jsonpath "$.content[0].mime_type" == "application/octet-stream"
