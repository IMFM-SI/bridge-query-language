"""The `Maniplexes` domain: regular rank-4 maniplexes, backed by
`data/sym-ob-small.db` (see `data/sym-ob-small-description.md`)."""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path

from mathql import codecs, schema

_DB_PATH = Path(__file__).resolve().parents[3] / "data" / "sym-ob-small.db"


def _attributes() -> dict[str, schema.Attribute]:
    return {
        "size": schema.Attribute(column="size", decode=codecs.identity, kind="integer"),
        "orientable": schema.Attribute(column="orientable", decode=codecs.boolean, kind="boolean"),
        "polytopality": schema.Attribute(column="polytopality", decode=codecs.identity, kind="string"),
        "symmetry_type": schema.Attribute(column="symmetry_type", decode=codecs.identity, kind="string"),
        "schlafli_symbol": schema.Attribute(
            column="schlafli_symbol", decode=codecs.json_value, kind="list of integers"
        ),
        "generators": schema.Attribute(
            column="generators", decode=codecs.json_value, kind="list of permutations"
        ),
        "color_group": schema.Attribute(
            column="color_group", decode=codecs.json_value, kind="list of permutations"
        ),
    }


def _represent(row: Mapping[str, object]) -> object:
    """Render a maniplex as its Schläfli symbol, flag count, and generators."""
    return {
        "size": row["size"],
        "schlafli_symbol": row["schlafli_symbol"],
        "orientable": row["orientable"],
        "polytopality": row["polytopality"],
        "generators": row["generators"],
    }


MANIPLEXES = schema.Database(
    path=_DB_PATH,
    domains={
        "Maniplexes": schema.Domain(
            table="maniplex",
            attributes=_attributes(),
            represent=_represent,
        )
    },
)
