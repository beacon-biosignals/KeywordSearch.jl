module KeywordSearch
using UUIDs
using StringDistances
using AbstractTrees
using Tables

export DamerauLevenshtein, FuzzyQuery, Query, Corpus, Document
export augment, explain, match_all, word_boundary, NamedQuery

@doc raw"""
    const AUTOMATIC_REPLACEMENTS::Vector{Pair{Union{Regex,String},String}}

A list of replacements to automatically perform when preprocessing a [`Document`](@ref).
For example, if `KeywordSearch.AUTOMATIC_REPLACEMENTS == ["a" => "b"]`, then
`Document("abc").text == "bbc"` instead of "abc".

By default, `AUTOMATIC_REPLACEMENTS` contains only one replacement,

```julia
r"[.!?><\-\n\r\v\t\f]" => " "
```

which replaces certain punctuation characters, whitespace, and newlines with a space.
This replacement is needed for [`word_boundary`](@ref) to work correctly, but you
can remove it with `empty!(KeywordSearch.AUTOMATIC_REPLACEMENTS)` if you wish.

You an also add other preprocessing directives by `push!`ing further replacements
into `KeywordSearch.AUTOMATIC_REPLACEMENTS`.
"""
const AUTOMATIC_REPLACEMENTS = Pair{Union{Regex,String},String}[r"[.!?><\-\n\r\v\t\f]" => " "]

include("core.jl")
include("corpus.jl")
include("names.jl")
include("printing.jl")
include("helpers.jl")

end # module
