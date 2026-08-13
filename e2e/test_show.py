"""show(): exec can emit binary/image content as extra content parts
alongside the text result.

Measured against the packed wasm rather than assumed from the old ACT-HTTP
wire shape: an `image/*` part becomes a native MCP `ImageContent` (mime on
its own `.mimeType` field, not `_meta`), while a non-image mime like
`application/octet-stream` stays a `TextContent` whose `.text` is the
base64 payload and whose mime lands in `_meta["dev.actcore/mime-type"]` —
the same split found migrating `anydoc`.
"""


async def test_png_part_alongside_the_text_result(client, exec_meta):
    # Hermetic (raw bytes, no Pillow) — the mime is sniffed from the leading
    # bytes (PNG magic here).
    code = r"show(b'\x89PNG\r\n\x1a\nFAKE'); 'img made'"
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert len(result.content) == 2
    text_part, image_part = result.content
    assert text_part.meta["dev.actcore/mime-type"] == "text/plain"
    assert "img made" in text_part.text
    assert image_part.mimeType == "image/png"
    assert image_part.data == "iVBORw0KGgpGQUtF"


async def test_explicit_mime_overrides_sniffing(client, exec_meta):
    code = "show(b'hello', 'application/octet-stream'); None"
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert len(result.content) == 1
    assert result.content[0].meta["dev.actcore/mime-type"] == "application/octet-stream"
