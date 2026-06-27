# Scientific tier: Pillow ImageFont — draw text on an image. Requires the sci
# build. load_default() needs no font file (built-in bitmap); ImageFont.truetype
# renders scalable fonts via freetype from a file (needs wasi:filesystem).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "from PIL import Image, ImageDraw, ImageFont\nimport io\nimg = Image.new('RGB', (140, 40), 'white')\nd = ImageDraw.Draw(img)\nd.text((5, 12), 'Hello ACT', fill='black', font=ImageFont.load_default())\nbuf = io.BytesIO(); img.save(buf, 'PNG')\n(buf.getvalue()[:4] == bytes([137,80,78,71]), len(buf.getvalue()) > 0)"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "(True, True)"
