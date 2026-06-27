# arithmetic
POST {{baseurl}}/tools/exec
{"arguments": {"code": "2 + 2"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "4"

# stdlib import + statement then expression
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import math\nmath.factorial(5)"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "120"
