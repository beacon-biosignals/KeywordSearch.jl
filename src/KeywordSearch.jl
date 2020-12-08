module KeywordSearch
using UUIDs
using StringDistances
using AbstractTrees
using Tables

export DamerauLevenshtein, FuzzyQuery, Query, Corpus, Document
export augment, explain, match_all, word_boundary, NamedQuery

"""
    const AUTOMATIC_REPLACEMENTS::Vector{Pair{String, String}}

A list of replacements to automatically perform when preprocessing a [`Document`](@ref).
For example, if `KeywordSearch.AUTOMATIC_REPLACEMENTS == ["a" => "b"]`, then
`Document("abc").text == "bbc"` instead of "abc".
"""
const AUTOMATIC_REPLACEMENTS = Pair{String, String}[]

include("core.jl")
include("corpus.jl")
include("names.jl")
include("printing.jl")
include("helpers.jl")

end # module
