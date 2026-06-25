import MathQL.Schema

/-! The databases MathQL can query, relative to the repository's `data/`
directory (paths assume the executable runs from the `MathQL/` package dir). -/

namespace MathQL

private def intAttr (name : String) : Attribute :=
  { name, column := name, ty := .int, kind := .int }

private def boolAttr (name : String) : Attribute :=
  { name, column := name, ty := .bool, kind := .bool }

private def optIntAttr (name : String) : Attribute :=
  { name, column := name, ty := .option .int, kind := .optionInt }

private def strAttr (name : String) : Attribute :=
  { name, column := name, ty := .string, kind := .string }

private def intListAttr (name : String) : Attribute :=
  { name, column := name, ty := .list .int, kind := .jsonIntList }

def smallGraphs : Database where
  path := "../data/graphs-small.db"
  domains := [{
    name := "SmallGraphs"
    table := "graph"
    attributes :=
      [strAttr "graph6", intListAttr "degree_sequence"] ++
      (["num_vertices", "num_edges", "min_degree", "max_degree", "num_components",
        "num_triangles", "clique_number", "independence_number", "chromatic_number",
        "automorphism_count"].map intAttr) ++
      (["is_regular", "is_connected", "is_tree", "is_forest", "is_bipartite",
        "is_planar", "is_eulerian"].map boolAttr) ++
      (["diameter", "radius", "girth"].map optIntAttr)
  }]

def maniplexes : Database where
  path := "../data/sym-ob-small.db"
  domains := [{
    name := "Maniplexes"
    table := "maniplex"
    attributes :=
      [intAttr "size", boolAttr "orientable", strAttr "polytopality",
       strAttr "symmetry_type", intListAttr "schlafli_symbol", strAttr "generators"]
  }]

def databases : List Database := [smallGraphs, maniplexes]

def ColumnKind.describe : ColumnKind → String
  | .int => "integer"
  | .bool => "boolean"
  | .string => "string"
  | .jsonIntList => "list of integers"
  | .optionInt => "integer or null"

/-- A JSON description of every domain and its invariants. -/
def catalogJson : String :=
  let domainJson (d : Domain) : String :=
    let attrs := ", ".intercalate (d.attributes.map fun a =>
      "{\"name\": \"" ++ a.name ++ "\", \"kind\": \"" ++ a.kind.describe ++ "\"}")
    "{\"domain\": \"" ++ d.name ++ "\", \"invariants\": [" ++ attrs ++ "]}"
  "[" ++ ", ".intercalate ((databases.flatMap (·.domains)).map domainJson) ++ "]"

end MathQL

