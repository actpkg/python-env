# Scientific tier: Pillow (PIL) image processing — create, transform, and encode
# PNG, in the wasm sandbox. Requires the sci build (`just build-sci`). PNG/BMP/GIF/
# PPM work; JPEG is not built in (its setjmp can't be folded — see README).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import io\nfrom PIL import Image, ImageOps\nim = ImageOps.grayscale(Image.new('RGB', (20, 10), (255, 0, 0)).rotate(90, expand=True))\nbuf = io.BytesIO(); im.save(buf, 'PNG'); d = buf.getvalue()\nf\"size={im.size} png={d[:4] == bytes([137,80,78,71])} mode={im.mode}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "size=(10, 20)"
jsonpath "$.content[0].data" contains "png=True"
jsonpath "$.content[0].data" contains "mode=L"

# Pillow <-> numpy interop (grayscale of pure red ≈ 76).
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import numpy as np; int(np.asarray(im).mean())"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "76"
