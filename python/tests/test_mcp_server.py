from __future__ import annotations

import asyncio

from mathql import mcp_server


def test_jsonable_turns_tuples_into_lists():
    assert mcp_server._jsonable((1, (2, 3), [4])) == [1, [2, 3], [4]]
    assert mcp_server._jsonable({"edges": (1, 2)}) == {"edges": [1, 2]}


def test_describe_schema_lists_domains():
    assert {"SmallGraphs", "Maniplexes"} <= set(mcp_server.describe_schema())


def test_server_registers_both_tools():
    tools = asyncio.run(mcp_server.server.list_tools())
    assert {"query", "describe_schema"} <= {tool.name for tool in tools}
