import QueryLanguage.Peano.ExampleDBSignature
import QueryLanguage.Peano.ExampleDB

namespace Peano.Example
  /-! Usage examples. Note that writing queries by hand is quite
      annoying at present, but we shall improve this bit. -/

  open Peano.Language
  open Peano.ExampleDBSignature
  open Peano.ExampleDB

  -- query: objects of size 10 whose first component of genus is even
  def my_query : Query O P D :=
    .conj
      (.pred .eq (.pair (.getAttr .size) (.call (.const 10) .tt)))
      (.pred .even (.fst (.getAttr .genus)))

  #eval Pasture.exec my_query

  -- query: objects of size 10 whose first component of genus is even,
  --        written using a high-level domain specific language (DSL)
  def my_query_dsl : Query O P D :=
    >>
    (get_size == 10)
    &&
    (even (fst (get_genus)))
    <<

  #eval Pasture.exec my_query_dsl

  -- both queries are parsed the same
  theorem equal_results : my_query = my_query_dsl := by rfl

end Peano.Example
