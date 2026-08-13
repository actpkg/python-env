async def test_lxml_html_xpath_by_class(client, exec_meta):
    # Scientific tier: lxml — fast XML/HTML parsing with XPath. Requires the
    # sci build (`just build sci`). Built against a wasi-cross libxml2 +
    # libxslt.
    code = (
        "from lxml import html\n"
        'doc = html.fromstring(\'<ul><li class="x">a</li><li class="x">b</li><li>c</li></ul>\')\n'
        "doc.xpath('//li[@class=\"x\"]/text()')"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "['a', 'b']"


async def test_lxml_xml_xpath_over_attributes(client, exec_meta):
    code = (
        "from lxml import etree\n"
        'r = etree.fromstring(\'<r><n v="1"/><n v="2"/><n v="3"/></r>\')\n'
        "sum(int(n.get('v')) for n in r.xpath('//n'))"
    )
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == "6"
