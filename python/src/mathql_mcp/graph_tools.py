"""networkx-backed tools that decode a graph6 string into structure.

These decode and inspect a `graph6` string returned by a query. Vertices are numbered
0..n-1.
"""

from typing import Any

import networkx
from mcp.server.fastmcp import FastMCP


def register(mcp: FastMCP) -> None:
    """Register the graph-inspection tools on `mcp`."""

    @mcp.tool()
    def edge_list(graph6: str) -> dict[str, Any]:
        """Decode a graph6 string to its edge list.

        Returns {"num_vertices": n, "edges": [[u, v], ...]} with vertices 0..n-1; the
        vertex count is included so that isolated vertices are counted.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        return {
            "num_vertices": g.number_of_nodes(),
            "edges": sorted([min(u, v), max(u, v)] for u, v in g.edges()),
        }

    @mcp.tool()
    def neighbors(graph6: str, vertex: int) -> list[int]:
        """The neighbors of `vertex` (0-indexed) in the graph6-encoded graph."""
        g = networkx.from_graph6_bytes(graph6.encode())
        return sorted(g.neighbors(vertex))

    @mcp.tool()
    def shortest_path(graph6: str, source: int, target: int) -> dict[str, Any]:
        """A shortest path between `source` and `target` (0-indexed).

        Two vertices in one component give {"length": k, "path": [source, ..., target]};
        two vertices in different components give {"length": null}.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        if networkx.has_path(g, source, target):
            path = networkx.shortest_path(g, source, target)
            return {"length": len(path) - 1, "path": path}
        else:
            return {"length": None}

    @mcp.tool()
    def max_clique(graph6: str) -> list[int]:
        """A maximum clique: a largest set of pairwise-adjacent vertices.

        Exact; its size is the graph's clique number.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        clique, _ = networkx.max_weight_clique(g, weight=None)
        return sorted(clique)

    @mcp.tool()
    def max_independent_set(graph6: str) -> list[int]:
        """A maximum independent set: a largest set of pairwise-nonadjacent vertices.

        Exact (a maximum clique of the complement); its size is the independence number.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        clique, _ = networkx.max_weight_clique(networkx.complement(g), weight=None)
        return sorted(clique)

    @mcp.tool()
    def connected_components(graph6: str) -> list[list[int]]:
        """The connected components, each as a sorted vertex list."""
        g = networkx.from_graph6_bytes(graph6.encode())
        return [sorted(component) for component in networkx.connected_components(g)]

    @mcp.tool()
    def coloring(graph6: str) -> dict[str, Any]:
        """A proper vertex coloring, computed greedily (DSATUR).

        Returns {"num_colors": k, "coloring": [[vertex, color], ...]} with colors
        0..k-1. The coloring is proper; the color count may exceed the graph's
        chromatic number.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        colors = networkx.greedy_color(g, strategy="DSATUR")
        num_colors = max(colors.values()) + 1 if colors else 0
        return {
            "num_colors": num_colors,
            "coloring": [[v, colors[v]] for v in sorted(colors)],
        }
