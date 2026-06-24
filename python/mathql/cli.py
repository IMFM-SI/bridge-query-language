"""Command-line interface: run a MathQL query and print its results as JSON."""

from __future__ import annotations

import argparse
import json

from mathql.databases.graphs import SMALL_GRAPHS
from mathql.engine import run

_DATABASES = {"graphs": SMALL_GRAPHS}


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="mathql", description="Query databases of mathematical objects."
    )
    parser.add_argument(
        "query",
        help='a MathQL query, e.g. "{ g.num_edges for g in SmallGraphs if g.is_tree }"',
    )
    parser.add_argument(
        "--database", choices=_DATABASES, default="graphs",
        help="database to query (default: graphs)",
    )
    parser.add_argument("--limit", type=int, help="print at most this many results")
    parser.add_argument("--count", action="store_true", help="print only the number of results")
    arguments = parser.parse_args(argv)

    results = run(arguments.query, _DATABASES[arguments.database])
    if arguments.count:
        print(len(results))
    else:
        for item in results[: arguments.limit]:
            print(json.dumps(item))
