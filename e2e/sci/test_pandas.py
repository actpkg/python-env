async def test_pandas_dataframe_groupby_and_time_series(client, exec_meta):
    # Scientific tier: pandas 3.0.3 (real Cython/C extensions) in a session.
    # Requires the sci build (`just build sci`) AND a wasm-EH act. Covers
    # DataFrame construction, reductions, groupby (the _libs
    # hashtable/groupby C extensions), and datetime/time-series (tslibs —
    # fixed via NPY_TARGET_VERSION=2.0 so pandas reads the numpy datetime
    # metadata correctly).
    construct = await client.call_tool(
        "exec",
        {
            "code": (
                "import pandas as pd; df=pd.DataFrame({'a':[1,2,3,4],'b':[10,20,30,40]}); "
                "f\"pandas {pd.__version__} sum={int(df['a'].sum())} mean={df['b'].mean()}\""
            ),
            "_meta": exec_meta,
        },
    )
    text = construct.content[0].text
    assert "pandas 3.0.3" in text
    assert "sum=10" in text
    assert "mean=25.0" in text

    # groupby across a session-persisted DataFrame (Cython _libs path).
    grouped = await client.call_tool(
        "exec",
        {"code": "df.groupby(df['a'] % 2)['b'].sum().to_dict()", "_meta": exec_meta},
    )
    assert grouped.content[0].text == "{0: 60, 1: 40}"

    # datetime/time-series: to_datetime, date_range, .dt accessor, timedelta.
    series = await client.call_tool(
        "exec",
        {
            "code": (
                "import pandas as pd; s=pd.to_datetime(['2026-01-01','2026-06-27']); "
                "dr=pd.date_range('2026-01-01', periods=3, freq='D'); "
                'f"years={list(s.year)} ndays={len(dr)} delta={(s[1]-s[0]).days}"'
            ),
            "_meta": exec_meta,
        },
    )
    text = series.content[0].text
    assert "years=[2026, 2026]" in text
    assert "ndays=3" in text
    assert "delta=177" in text
