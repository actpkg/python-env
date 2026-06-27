# Scientific tier: the `regex` C extension (faster/extended `re`). Requires the
# sci build (`just build-sci`). Exercises features stdlib `re` lacks: fuzzy
# (approximate) matching and Unicode property classes.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import regex; regex.search('(?:colour){e<=1}', 'my color here').group()"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "'color'"

POST {{baseurl}}/tools/exec
{"arguments": {"code": "import regex; regex.findall('\\\\p{Lu}', 'Hello World ABC')"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "['H', 'W', 'A', 'B', 'C']"
