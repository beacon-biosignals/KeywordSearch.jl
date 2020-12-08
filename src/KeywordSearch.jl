module KeywordSearch
using UUIDs
using StringDistances
using AbstractTrees
using Tables

export DamerauLevenshtein, FuzzyQuery, Query, Patient, Report
export augment, explain, match_all, word_boundary, NamedQuery

"""
    const AUTOMATIC_REPLACEMENTS::Vector{Pair{String, String}}

A list of replacements to automatically perform when preprocessing a [`Report`](@ref).
For example, if `KeywordSearch.AUTOMATIC_REPLACEMENTS == ["a" => "b"]`, then
`Report("abc").text == "bbc"` instead of "abc".
"""
const AUTOMATIC_REPLACEMENTS = Pair{String, String}[]

include("match.jl")
include("core.jl")
include("patient.jl")
include("names.jl")
include("printing.jl")
include("helpers.jl")

end # module
