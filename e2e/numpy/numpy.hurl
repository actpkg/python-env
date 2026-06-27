# Scientific tier: numpy 2.5.0 in a session. Requires the numpy build
# (`just build-numpy`) AND a wasm-EH-enabled act runtime (numpy 2.x's pocketfft
# uses C++ exceptions). std() exercises that exception path.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import numpy as np; f'numpy {np.__version__} mean={np.arange(10).mean()} std={np.std(np.arange(10)):.4f}'"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "numpy 2.5.0"
jsonpath "$.content[0].data" contains "mean=4.5"
jsonpath "$.content[0].data" contains "std=2.8723"

# `np` persists in the session namespace across calls (set by the previous exec).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "list(map(int, (np.ones((3,3)) @ np.ones((3,3))).diagonal()))"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "[3, 3, 3]"
