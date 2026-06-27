# Scientific tier: Pillow renders a real PNG and exec returns it as an image/png
# content part via show(). Requires the sci build (`just build-sci`).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import io\nfrom PIL import Image\nbuf = io.BytesIO(); Image.new('RGB', (8, 8), (0, 128, 255)).save(buf, 'PNG')\nshow(buf.getvalue())\nf'rendered {len(buf.getvalue())} bytes'"}}
HTTP 200
[Asserts]
jsonpath "$.content" count == 2
jsonpath "$.content[0].data" contains "rendered"
jsonpath "$.content[1].mime_type" == "image/png"
