# Scientific tier: pandas 3.0.3 (real Cython/C extensions) in a session. Requires
# the sci build (`just build-sci`) AND a wasm-EH act. Covers DataFrame construction,
# reductions, groupby (the _libs hashtable/groupby C extensions), and datetime /
# time-series (tslibs — fixed via NPY_TARGET_VERSION=2.0 so pandas reads the numpy
# datetime metadata correctly).
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

# datetime / time-series: to_datetime, date_range, .dt accessor, timedelta.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import pandas as pd; s=pd.to_datetime(['2026-01-01','2026-06-27']); dr=pd.date_range('2026-01-01', periods=3, freq='D'); f\"years={list(s.year)} ndays={len(dr)} delta={(s[1]-s[0]).days}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "years=[2026, 2026]"
jsonpath "$.content[0].data" contains "ndays=3"
jsonpath "$.content[0].data" contains "delta=177"
