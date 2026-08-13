async def test_pillow_jpeg_encode_and_decode(client, exec_meta):
    # Scientific tier: Pillow JPEG encode + decode. Requires the sci build.
    # JPEG uses libjpeg's setjmp, folded via the tag-skip componentize-py +
    # modern try_table EH.
    code = (
        "import io\n"
        "from PIL import Image\n"
        "buf = io.BytesIO(); Image.new('RGB', (32, 24), (200, 100, 50)).save(buf, 'JPEG', quality=85)\n"
        "jpg = buf.getvalue()\n"
        "im = Image.open(io.BytesIO(jpg)); im.load()\n"
        'f"jpeg_magic={jpg[:3] == bytes([255,216,255])} size={im.size} mode={im.mode}"'
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    text = result.content[0].text
    assert "jpeg_magic=True" in text
    assert "size=(32, 24)" in text
    assert "mode=RGB" in text
