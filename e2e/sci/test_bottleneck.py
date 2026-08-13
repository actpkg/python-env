async def test_bottleneck_nan_aware_reductions(client, exec_meta):
    # Scientific tier: bottleneck — fast NaN-aware array reductions over
    # numpy. Requires the sci build (`just build sci`). Accelerates
    # pandas-style stats.
    code = (
        "import bottleneck as bn, numpy as np\n"
        "a = np.array([1.0, np.nan, 3.0, np.nan, 5.0])\n"
        "(bn.nanmean(a), bn.nansum(a), bn.nanmax(a))"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "(3.0, 9.0, 5.0)"
