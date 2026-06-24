from __future__ import annotations

import pytest

from mathql import catalog


def test_lists_all_domains():
    assert {"SmallGraphs", "Maniplexes"} <= set(catalog.domains())


def test_routes_domain_to_its_database():
    assert catalog.database_for("SmallGraphs").path.name == "graphs-small.db"
    assert catalog.database_for("Maniplexes").path.name == "sym-ob-small.db"


def test_unknown_domain_raises():
    with pytest.raises(KeyError):
        catalog.database_for("Nonexistent")
