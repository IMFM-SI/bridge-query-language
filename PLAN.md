# A query language for databases of mathematical objects

We are going to design a query language that can be used by an AI agent or human
to query databases of mathematical objects. The empahsis is on AI agents, who will
access databases through MCP by issuing queries written in our query language.

There will be multiple databases, some might be local, some might be remote,
and some might even be computed on the fly. The query langauge is the unifying interface.

A database contains one or more tables, possibly related to each other, describing a collection
of mathematical objects together with a selection of their invariants. The invariants may be complex.
Some values may be missing (an invariant that is too hard to compute for a specific object).

Our query language should be robust with respect to such missing information, but perhaps the user should have the option of specifying whether they want to over- or under-approximate the results (if a value is missing, assume the basic attribute referencing it to be `false` or to be `true`?)

The mathematical content and the information available in a given database will be described
in some standard way. This can be a Python class, for example, that tells how the query language
connects to the database.

From users's (an AI agent) point of view, the database appears as a collection of *mathematical objects*.
The objects themselves thus need to be represented in some form that can be understood by the agent.
For example, a graph may be represented by an adjancency list, a list of edges, or some other form.
Perhaps we need to support several formats of output for the same database, and the user can choose one of them - but let's start simple.

A query should be a boolean expression whose atomic propositions are assertions about the invariants. For the time being, we do not want to allow referring to the object itself, only to the invariants stored in the database.

Everything should be well-typed, but the typing system should not be complicated.

It is likely that not every query will be directly translated into SQL, in which case we would want to generate
and SQL *over-approximation* (returns too many objects) which we then filter additionally. However, the first prototypes
should not worry about this possibility.

We need to write the queries in some form that allows the user to explain what is searched, what is returned, in what order. Something like Python-style list comprehensions might work, for instance:

    [ (g.chromatic_number, g.edgeList) for g in smallGraph.graph if (g.vertexSize < 5 && g.girth == 7) ].sorted(key=g.vertexSize)

This is very Python-ish and possibly quite annoying to parse. It should be designed so that AI agents can write such queries,
they're easy to parse, but they can also control things like "which objects from which database to search through", how to sort,
how to limit the number of results, etc.
