async def test_pillow_draws_text_with_the_built_in_bitmap_font(client, exec_meta):
    # Scientific tier: Pillow ImageFont — draw text on an image. Requires the
    # sci build. load_default() needs no font file (built-in bitmap);
    # ImageFont.truetype renders scalable fonts via freetype from a file
    # (needs wasi:filesystem).
    code = (
        "from PIL import Image, ImageDraw, ImageFont\n"
        "import io\n"
        "img = Image.new('RGB', (140, 40), 'white')\n"
        "d = ImageDraw.Draw(img)\n"
        "d.text((5, 12), 'Hello ACT', fill='black', font=ImageFont.load_default())\n"
        "buf = io.BytesIO(); img.save(buf, 'PNG')\n"
        "(buf.getvalue()[:4] == bytes([137,80,78,71]), len(buf.getvalue()) > 0)"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "(True, True)"
