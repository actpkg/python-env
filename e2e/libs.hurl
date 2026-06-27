# Smoke test: all 12 bundled pure-Python libraries can be imported in one session.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import jinja2, markdown, bs4, rich, tabulate, slugify, yaml, dateutil, attr, more_itertools, sortedcontainers, mpmath\nprint('all imported')"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "all imported"
