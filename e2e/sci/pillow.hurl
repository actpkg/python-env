# Scientific tier: Pillow (PIL) image processing — create, transform, encode PNG,
# and numpy interop, in the wasm sandbox. Requires the sci build (`just build-sci`).
# Self-contained (one request) so it doesn't depend on shared-session state.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "import io\nfrom PIL import Image, ImageOps\nimport numpy as np\nim = ImageOps.grayscale(Image.new('RGB', (20, 10), (255, 0, 0)).rotate(90, expand=True))\nbuf = io.BytesIO(); im.save(buf, 'PNG'); d = buf.getvalue()\n# grayscale of pure red ≈ 76\nf\"size={im.size} png={d[:4] == bytes([137,80,78,71])} mode={im.mode} mean={int(np.asarray(im).mean())}\""}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" contains "size=(10, 20)"
jsonpath "$.content[0].data" contains "png=True"
jsonpath "$.content[0].data" contains "mode=L"
jsonpath "$.content[0].data" contains "mean=76"
