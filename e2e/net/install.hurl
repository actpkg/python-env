# Install a tiny pure-Python package at runtime, then import it in the default
# session. NOTE: this test makes a real HTTPS request to pypi.org +
# files.pythonhosted.org; it requires outbound network.
POST {{baseurl}}/tools/install
{"arguments": {"package": "six"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "installed six"

# six is now importable (installs are process-global, visible to the session).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import six; six.__version__"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" matches "^'\\d+\\.\\d+"

# A stdlib-heavy pure-Python package: sympy imports `timeit` (full-stdlib freeze)
# and `ctypes` (WASI-absent → stub). Proves `install` works beyond trivial wheels.
POST {{baseurl}}/tools/install
{"arguments": {"package": "sympy"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "installed sympy"

POST {{baseurl}}/tools/exec
{"arguments": {"code": "import sympy; str(sympy.factorint(360))"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "'{2: 3, 3: 2, 5: 1}'"
