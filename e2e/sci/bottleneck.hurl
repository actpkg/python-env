# Scientific tier: bottleneck — fast NaN-aware array reductions over numpy.
# Requires the sci build (`just build-sci`). Accelerates pandas-style stats.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import bottleneck as bn, numpy as np\na = np.array([1.0, np.nan, 3.0, np.nan, 5.0])\n(bn.nanmean(a), bn.nansum(a), bn.nanmax(a))"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "(3.0, 9.0, 5.0)"
