async def test_pillow_renders_a_real_png_via_show(client, exec_meta):
    # Scientific tier: Pillow renders a real PNG and exec returns it as an
    # image/png content part via show(). Requires the sci build (`just build
    # sci`).
    code = (
        "import io\n"
        "from PIL import Image\n"
        "buf = io.BytesIO(); Image.new('RGB', (8, 8), (0, 128, 255)).save(buf, 'PNG')\n"
        "show(buf.getvalue())\n"
        "f'rendered {len(buf.getvalue())} bytes'"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert len(result.content) == 2
    text_part, image_part = result.content
    assert "rendered" in text_part.text
    assert image_part.mimeType == "image/png"
