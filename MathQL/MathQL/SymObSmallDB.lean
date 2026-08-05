import MathQL.Ty
import MathQL.Database
import Lean.Data.Json

/-!
# `sym-ob-small.db` — a MathQL `Database`

Source: `data/sym-ob-small.db` (regular rank-4 maniplexes with their flag
graphs, skeleta, and canonical labelings); described in
`data/sym-ob-small-description.md`. Five domains: `Maniplex` links through
`CanonicalLabeling` to `Graph`, so reaching a maniplex's flag graph is a
two-hop chain of domain fields.
-/

namespace MathQL.SymObSmallDB

/-- The column list from `(label, column, type, doc)` rows; the `id` label is
the primary key throughout this database. -/
private def columns (rows : List (String × String × Ty × String)) : List (Label × Column) :=
  rows.map fun (label, column, ty, doc) =>
    (.label label, { column, ty, isPrimary := label == "id", doc })

/-- The foreign-key list from `(label, column, domain, doc)` rows; every foreign
key in this database points at the linked table's `id`. -/
private def foreignKeys (rows : List (String × String × String × String)) :
    List (Label × ForeignKey) :=
  rows.map fun (label, column, domain, doc) =>
    (.label label, { domain := .domain domain, column := [(column, "id")], doc })

/-- The `Graph` domain over the `graph` table: undirected graphs in sparse6
encoding, serving as flag graphs, 1-skeleta, and 1-coskeleta. -/
def graphDomain : Schema where
  table := "graph"
  column := columns
    [ ("id", "id", .int, "the graph's identifier"),
      ("sparse6", "graph_in_sparse6", .string, "the graph in sparse6 encoding"),
      ("num_vertices", "order", .int, "order: the number of vertices"),
      ("num_edges", "size", .int, "size: the number of edges"),
      ("degree_sequence", "degree_sequence", .list .int, "the vertex degrees") ]
  foreignKey := []
  doc := "An undirected graph: a flag graph, 1-skeleton, or 1-coskeleton of a maniplex."

/-- The `CanonicalLabeling` domain over the `canonicallabeling` table. -/
def canonicalLabelingDomain : Schema where
  table := "canonicallabeling"
  column := columns
    [ ("id", "id", .int, "the labeling's identifier"),
      ("vertex_order", "vertices_in_canonical_order", .list .int,
        "the vertices in canonical order") ]
  foreignKey := foreignKeys
    [ ("graph", "graph_in_sparse6_id", "Graph", "the labeled graph"),
      ("parameters", "parameters_id", "LabelingParameters",
        "the labeling-tool configuration that produced it") ]
  doc := "A canonical vertex ordering of a graph, produced by a labeling tool."

/-- The `Maniplex` domain over the `maniplex` table. -/
def maniplexDomain : Schema where
  table := "maniplex"
  column := columns
    [ ("id", "id", .int, "the maniplex's identifier"),
      ("num_flags", "size", .int, "the number of flags"),
      ("schlafli_symbol", "schlafli_symbol", .prod [.int, .int, .int],
        "the Schläfli symbol (p, q, r): p-gonal 2-faces, q-gonal vertex figures, \
         r-gonal edge figures"),
      ("generators", "generators", .prod [.list .int, .list .int, .list .int, .list .int],
        "the connection-group generators r0, r1, r2, r3"),
      ("orientable", "orientable", .bool, "whether the maniplex is orientable"),
      ("polytopality", "polytopality", .string,
        "'Polytopal', 'Faithful', or 'Unfaithful'"),
      ("edge_coloring", "cl_fg_edge_coloring", .string,
        "the edge coloring of the flag graph, encoded"),
      ("one_skeleton", "one_skeleton", .string,
        "the 1-skeleton as an adjacency description"),
      ("one_coskeleton", "one_coskeleton", .string,
        "the 1-coskeleton as an adjacency description"),
      ("color_group", "color_group", .list (.list .int),
        "the color-symmetry group as permutations; empty when trivial"),
      ("symmetry_type", "symmetry_type", .string,
        "the symmetry type; 'regular' throughout this census") ]
  foreignKey := foreignKeys
    [ ("flag_graph", "cl_flag_graph_id", "CanonicalLabeling",
        "the canonically labeled flag graph"),
      ("skeleton", "cl_one_skeleton_id", "CanonicalLabeling",
        "the canonically labeled 1-skeleton"),
      ("coskeleton", "cl_one_coskeleton_id", "CanonicalLabeling",
        "the canonically labeled 1-coskeleton") ]
  doc := "A regular rank-4 maniplex: a set of flags with four adjacency involutions."

/-- The `LabelingParameters` domain over the `clparameters` table. -/
def labelingParametersDomain : Schema where
  table := "clparameters"
  column := columns
    [ ("id", "id", .int, "the configuration's identifier"),
      ("software", "software", .string, "the labeling tool"),
      ("version", "version", .string, "the tool's version"),
      ("prefix", "prefix", .string, "invocation arguments before the input"),
      ("suffix", "suffix", .string, "invocation arguments after the input") ]
  foreignKey := []
  doc := "A labeling-tool configuration used to compute canonical labelings."

/-- The `GraphExternalReference` domain over the `graphexternalreference` table. -/
def graphExternalReferenceDomain : Schema where
  table := "graphexternalreference"
  column := columns
    [ ("id", "id", .int, "the reference's identifier"),
      ("source", "source", .string, "the external collection, e.g. 'HoG'"),
      ("external_id", "id_source", .string, "the identifier within that collection") ]
  foreignKey := foreignKeys
    [ ("graph", "graph_id", "Graph", "the referenced graph") ]
  doc := "A cross-reference from a graph to an external census or database."

/-- The `sym-ob-small.db` database. -/
def database : Database where
  overview := "Regular rank-4 maniplexes (32 634 of them) with their flag graphs, \
    1-skeleta, 1-coskeleta, and canonical labelings. A maniplex links to a \
    CanonicalLabeling through flag_graph, skeleton, and coskeleton; a labeling \
    links to its Graph."
  const := []
  domain :=
    [ (.domain "Maniplex", maniplexDomain),
      (.domain "CanonicalLabeling", canonicalLabelingDomain),
      (.domain "Graph", graphDomain),
      (.domain "LabelingParameters", labelingParametersDomain),
      (.domain "GraphExternalReference", graphExternalReferenceDomain) ]
  sqlFunction := []
  postFunction := []
  examples :=
    [ ("orientable polytopal maniplexes of type (4, 8, 8)",
        json% { "domains": [["m", "Maniplex"]],
                "output": [["id", "id(m)"], ["flags", "m.num_flags"]],
                "condition": "m.orientable && m.polytopality == 'Polytopal' && m.schlafli_symbol == (4, 8, 8)",
                "limit": 5 }),
      ("the skeleta of the smallest polytopal maniplexes, via the two-hop chain",
        json% { "domains": [["m", "Maniplex"]],
                "output": [["id", "id(m)"],
                           ["flags", "m.num_flags"],
                           ["skeleton6", "m.skeleton.graph.sparse6"]],
                "condition": "m.polytopality == 'Polytopal'",
                "order": [["flags", "asc"]],
                "limit": 5 }),
      ("self-dual maniplexes: the skeleton and coskeleton are the same graph",
        json% { "domains": [["m", "Maniplex"]],
                "output": [["id", "id(m)"], ["graph_id", "id(m.skeleton.graph)"]],
                "condition": "id(m.skeleton.graph) == id(m.coskeleton.graph)",
                "limit": 5 }),
      ("maniplexes with a nontrivial color group, most flags first",
        json% { "domains": [["m", "Maniplex"]],
                "output": [["id", "id(m)"], ["flags", "m.num_flags"]],
                "condition": "m.color_group != []",
                "order": [["flags", "desc"]],
                "limit": 5 }),
      ("graphs referenced in the House of Graphs, with their vertex counts",
        json% { "domains": [["r", "GraphExternalReference"]],
                "output": [["hog", "r.external_id"], ["vertices", "r.graph.num_vertices"]],
                "condition": "r.source == 'HoG'",
                "limit": 5 }) ]

end MathQL.SymObSmallDB
