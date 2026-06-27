# Scientific tier: Pillow JPEG encode + decode. Requires the sci build. JPEG uses
# libjpeg's setjmp, folded via the tag-skip componentize-py + modern try_table EH.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import io\nfrom PIL import Image\nbuf = io.BytesIO(); Image.new('RGB', (32, 24), (200, 100, 50)).save(buf, 'JPEG', quality=85)\njpg = buf.getvalue()\nim = Image.open(io.BytesIO(jpg)); im.load()\nf\"jpeg_magic={jpg[:3] == bytes([255,216,255])} size={im.size} mode={im.mode}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "jpeg_magic=True"
jsonpath "$.content[0].data" contains "size=(32, 24)"
jsonpath "$.content[0].data" contains "mode=RGB"
