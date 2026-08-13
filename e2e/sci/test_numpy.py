async def test_numpy_stats_in_a_session(client, exec_meta):
    # Scientific tier: numpy 2.5.0 in a session. Requires the numpy build
    # (`just build-numpy`) AND a wasm-EH-enabled act runtime (numpy 2.x's
    # pocketfft uses C++ exceptions). std() exercises that exception path.
    code = "import numpy as np; f'numpy {np.__version__} mean={np.arange(10).mean()} std={np.std(np.arange(10)):.4f}'"
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    text = result.content[0].text
    assert "numpy 2.5.0" in text
    assert "mean=4.5" in text
    assert "std=2.8723" in text

    # `np` persists in the session namespace across calls (set above).
    matmul = await client.call_tool(
        "exec",
        {
            "code": "list(map(int, (np.ones((3,3)) @ np.ones((3,3))).diagonal()))",
            "_meta": exec_meta,
        },
    )
    assert matmul.content[0].text == "[3, 3, 3]"
