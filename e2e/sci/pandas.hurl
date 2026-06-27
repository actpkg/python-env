# Scientific tier: pandas 3.0.3 (real Cython/C extensions) in a session. Requires
# the sci build (`just build-sci`) AND a wasm-EH act. Covers DataFrame construction,
# reductions, and groupby (exercises the _libs hashtable/groupby C extensions).
# NOTE: datetime/time-series is a known limitation in this build (numpy datetime
# metadata ABI under investigation) — not covered here.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import pandas as pd; df=pd.DataFrame({'a':[1,2,3,4],'b':[10,20,30,40]}); f\"pandas {pd.__version__} sum={int(df['a'].sum())} mean={df['b'].mean()}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "pandas 3.0.3"
jsonpath "$.content[0].data" contains "sum=10"
jsonpath "$.content[0].data" contains "mean=25.0"

# groupby across a session-persisted DataFrame (Cython _libs path).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "df.groupby(df['a'] % 2)['b'].sum().to_dict()"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "{0: 60, 1: 40}"
