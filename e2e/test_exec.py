"""exec: run Python against this session's persistent namespace."""

import pytest

CASES = [
    ("2 + 2", "4"),  # arithmetic
    (
        "import math\nmath.factorial(5)",
        "120",
    ),  # stdlib import + statement then expression
]


@pytest.mark.parametrize("code,expected", CASES)
async def test_exec_result(client, exec_meta, code, expected):
    result = await client.call_tool("exec", {"code": code, "_meta": exec_meta})
    assert result.content[0].text == expected
