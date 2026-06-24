"""Running a MathQL query against a database.

`run` carries a query through the pipeline: parse, type-check (currently a
stub), compile the condition to SQL, fetch the matching rows, apply any
residual filter in Python, and compute the returned value for each object.
"""

from __future__ import annotations

import sqlite3

from mathql import compiler, schema
from mathql.parser import parse
from mathql.typecheck import typecheck


def run(text: str, database: schema.Database) -> list[object]:
    """Parse and execute `text` against `database`, returning the list of values
    the query produces — one per object that satisfies its condition."""
    query = parse(text)
    domain = database.domains[query.domain]
    typecheck(query, domain)
    where, params, residual = compiler.compile_condition(query.condition, domain)

    attributes = list(domain.attributes.items())
    columns = ", ".join(attribute.column for _, attribute in attributes)
    statement = f"SELECT {columns} FROM {domain.table} WHERE {where}"

    connection = sqlite3.connect(f"file:{database.path}?mode=ro", uri=True)
    try:
        rows = connection.execute(statement, params).fetchall()
    finally:
        connection.close()

    results = []
    for raw in rows:
        row = {name: attribute.decode(raw[i]) for i, (name, attribute) in enumerate(attributes)}
        if residual is None or bool(compiler.evaluate(residual, row, domain)):
            results.append(compiler.evaluate(query.result, row, domain))
    return results
