# define a variable in one call
POST {{baseurl}}/tools/exec
{"arguments": {"code": "counter = 100"}}
HTTP 200

# a function in another call
POST {{baseurl}}/tools/exec
{"arguments": {"code": "def bump():\n    global counter\n    counter += 1\n    return counter"}}
HTTP 200

# use both — state persisted across all three calls
POST {{baseurl}}/tools/exec
{"arguments": {"code": "bump(); bump(); counter"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "102"
