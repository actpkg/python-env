async def test_pillow_transform_encode_and_numpy_interop(client, exec_meta):
    # Scientific tier: Pillow (PIL) image processing — create, transform,
    # encode PNG, and numpy interop, in the wasm sandbox. Requires the sci
    # build (`just build sci`). Self-contained (one request) so it doesn't
    # depend on shared-session state.
    code = (
        "import io\n"
        "from PIL import Image, ImageOps\n"
        "import numpy as np\n"
        "im = ImageOps.grayscale(Image.new('RGB', (20, 10), (255, 0, 0)).rotate(90, expand=True))\n"
        "buf = io.BytesIO(); im.save(buf, 'PNG'); d = buf.getvalue()\n"
        "# grayscale of pure red ≈ 76\n"
        'f"size={im.size} png={d[:4] == bytes([137,80,78,71])} mode={im.mode} mean={int(np.asarray(im).mean())}"'
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    text = result.content[0].text
    assert "size=(10, 20)" in text
    assert "png=True" in text
    assert "mode=L" in text
    assert "mean=76" in text
