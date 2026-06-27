# Scientific tier: lxml — fast XML/HTML parsing with XPath. Requires the sci
# build (`just build-sci`). Built against a wasi-cross libxml2 + libxslt.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "from lxml import html\ndoc = html.fromstring('<ul><li class=\"x\">a</li><li class=\"x\">b</li><li>c</li></ul>')\ndoc.xpath('//li[@class=\"x\"]/text()')"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "['a', 'b']"

# XML + XPath over attributes.
POST {{baseurl}}/tools/exec
{"arguments": {"code": "from lxml import etree\nr = etree.fromstring('<r><n v=\"1\"/><n v=\"2\"/><n v=\"3\"/></r>')\nsum(int(n.get('v')) for n in r.xpath('//n'))"}}
HTTP 200
[Asserts]
jsonpath "$.content[0].data" == "6"
