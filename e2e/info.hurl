GET {{baseurl}}/info
HTTP 200
[Asserts]
jsonpath "$.std.name" == "python-env"
jsonpath "$.std.version" isString
