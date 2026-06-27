"""networkx-backed tools that decode a graph6 string into structure.

These run on the Python side after the engine returns rows, so they decode and inspect
a graph; they are not queryable fields. Vertices are numbered 0..n-1.
"""

import networkx

from mcp.server.fastmcp import FastMCP


def register(mcp: FastMCP) -> None:
    """Register the graph-inspection tools on `mcp`."""

    @mcp.tool()
    def edge_list(graph6: str) -> dict:
        """Decode a graph6 string to its edge list.

        Returns {"num_vertices": n, "edges": [[u, v], ...]} with vertices 0..n-1; the
        vertex count is included so isolated vertices are not lost.
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
    def shortest_path(graph6: str, source: int, target: int) -> dict:
        """A shortest path between `source` and `target` (0-indexed).

        Returns {"length": k, "path": [source, ..., target]}; "path" is absent and
        "length" is null when the two vertices lie in different components.
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
    def coloring(graph6: str) -> dict:
        """A proper vertex coloring, computed greedily (DSATUR).

        Returns {"num_colors": k, "coloring": [[vertex, color], ...]} with colors
        0..k-1. The coloring is proper but heuristic: it may use more colors than the
        graph's chromatic number.
        """
        g = networkx.from_graph6_bytes(graph6.encode())
        colors = networkx.greedy_color(g, strategy="DSATUR")
        num_colors = max(colors.values()) + 1 if colors else 0
        return {
            "num_colors": num_colors,
            "coloring": [[v, colors[v]] for v in sorted(colors)],
        }
