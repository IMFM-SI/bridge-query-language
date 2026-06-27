# MathQL

MathQL is a query language for databasess of mathematical objects, such as groups,
graphs, knots, lattices, regular maps, abstract polytopes, etc.  Such objects are stored
together with a collection of computed invariants that MathQL may query.

The intended user for MatQL is an automated agent accessing it through MCP.

A database comprises several **domains**, each of which is a coherent collection
of mathematical objects. In the database it corresponds to a table or a view,
while in the query langauge it appears as a domain of a variable.

A MathQL query is a JSON object. It specifies which domains the query ranges over,
what condition the objects need to satisfy, and what information should be returned as
the result of the query. The results may be ordered by a given sorting key, and their
number can be limited.

A query is parsed, type-checked, compiled to SQL, executed by the database, and the
results are returned in JSON format.

MathQL is implemented in Lean 4 and reaches SQLite through the `leansqlite` bindings.
The MCP server that exposes MathQL to an agent is implemented in Python.
