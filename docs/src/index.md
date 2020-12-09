# KeywordSearch.jl

KeywordSearch has two main nouns:

* queries, which come in two flavors, [`Query`](@ref), which is used for exact matches, and [`FuzzyQuery`](@ref) which is for fuzzy matches
* and documents, which are strings wrapped in [`Document`](@ref) objects and can optionally have metadata associated with them.

Documents may also be collected into a [`Corpus`](@ref), which is simply a `Vector` of `Document`s
with additional metadata. Here, metadata simply refers to any `NamedTuple` stored in the `.metadata` field of the object.

Queries are used to search `Document`s or `Corpus`s via [`Base.match`](@ref) or [`match_all`](@ref). If no match is found, `nothing` is returned;
otherwise, a [`KeywordSearch.QueryMatch`](@ref) object is returned which contains details of the match.

## Contents

```@contents
```
