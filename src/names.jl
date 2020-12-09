
"""
    NamedMatch{T,M<:QueryMatch}

This object has two fields,

* `match::M`, which holds a `QueryMatch` object corresponding to the match
* and `metadata::T`, which holds a `NamedTuple` of metadata.

and is created by the method [`match(query::NamedQuery, obj)`](@ref).

`NamedMatch` satisfies the Tables.jl `AbstractRow` interface. This means that
a vector of `NamedMatch` objects is a valid Tables.jl-compatible table.

## Example

```jldoctest
julia> document_1 = Document("one", (; document_name = "a"))
Document with text "one ". Metadata: (document_name = "a",)

julia> document_2 = Document("Two but there's also a one here.", (; document_name = "b"))
Document starting with "Two but there's…". Metadata: (document_name = "b",)

julia> query = NamedQuery(Query("one"), "find one")
NamedQuery
├─ (query_name = "find one",)
└─ Query("one")

julia> matches = match_all(query, Corpus([document_1, document_2], (;corpus_name="corpus")));


julia> using Tables


julia> Tables.istable(matches)
true

julia> Tables.schema(Tables.rowtable(matches))
Tables.Schema:
 :haystack       Document{NamedTuple{(:document_name,),Tuple{String}}}
 :distance       Int64
 :indices        UnitRange{Int64}
 :query          Query
 :query_name     String
 :corpus_name    String
 :document_name  String

```
"""
struct NamedMatch{T,M<:QueryMatch}
    match::M
    metadata::T
    function NamedMatch(match::M, metadata::T) where {M,T}
        check_keys(T)
        return new{T,M}(match, metadata)
    end
end

function Tables.getcolumn(m::NamedMatch, i::Int)
    if i === 1
        return m.match.query
    elseif i === 2
        return m.match.haystack
    elseif i === 3
        return m.match.distance
    elseif i === 4
        return m.match.indices
    else
        return m.metadata[i - 4]
    end
end

function Tables.getcolumn(m::NamedMatch, s::Symbol)
    if s === :query
        return m.match.query
    elseif s === :haystack
        return m.match.haystack
    elseif s === :distance
        return m.match.distance
    elseif s === :indices
        return m.match.indices
    else
        return m.metadata[s]
    end
end

function Tables.columnnames(m::NamedMatch)
    return (:haystack, :distance, :indices, :query, keys(m.metadata)...)
end
Tables.isrowtable(::Type{<:AbstractVector{<:NamedMatch}}) = true

explain(io::IO, m::NamedMatch; context=40) = explain(io, m.match; context=context)

struct NamedQuery{T<:NamedTuple,Q<:AbstractQuery} <: AbstractQuery
    query::Q
    metadata::T

    function NamedQuery(query::Q, metadata::T) where {T,Q}
        check_keys(T)
        return new{T,Q}(query, metadata)
    end
end

function NamedQuery(query::AbstractQuery, name::AbstractString)
    return NamedQuery(query, (; query_name=name))
end

# Here, it seems like we could just dispach on `obj::Union{Corpus, Document}`.
# However, that leads to an ambiguity with `match(query::KeywordSearch.AbstractQuery, p::Corpus)`
# in `src/corpus.jl`. We solve that by creating a separate methods for `Document`s and `Corpus`s
# here.
for OT in (:Corpus, :Document)
    @eval function Base.match(Q::NamedQuery, obj::$(OT))
        disjoint_keys_check(Q, obj)
        m = match(Q.query, obj)
        m === nothing && return nothing
        return NamedMatch(m, (; Q.metadata..., obj.metadata..., m.haystack.metadata...))
    end

    @eval function match_all(Q::NamedQuery, obj::$(OT))
        disjoint_keys_check(Q, obj)
        matches = match_all(Q.query, obj)
        return [NamedMatch(m, (; Q.metadata..., obj.metadata..., m.haystack.metadata...))
                for m in matches]
    end
end

"""
    NamedQuery(metadata::Union{String, NamedTuple}, query::AbstractQuery)

Creates a `NamedQuery` that stores a metadata field holding information
about the query. When used with `match`, returns a [`NamedMatch`](@ref), which
carries the metadata of the `NamedQuery` as well as the metadata of the
object which was matched.

## Example

```jldoctest
julia> document_1 = Document("One", (; document_name = "a"))
Document with text "One ". Metadata: (document_name = "a",)

julia> document_2 = Document("Two", (; document_name = "b"))
Document with text "Two ". Metadata: (document_name = "b",)

julia> corpus = Corpus([document_1, document_2], (; corpus_name = "Numbers"))
Corpus with 2 documents, each with metadata keys: (:document_name,)
Corpus metadata: (corpus_name = "Numbers",)

julia> query = NamedQuery(FuzzyQuery("one"), "find one")
NamedQuery
├─ (query_name = "find one",)
└─ FuzzyQuery("one", DamerauLevenshtein{Nothing}(nothing), 2)

julia> m = match(query, corpus)
NamedMatch
├─ (query_name = "find one", corpus_name = "Numbers", document_name = "a")
└─ QueryMatch with distance 1 at indices 1:3.
   ├─ FuzzyQuery("one", DamerauLevenshtein{Nothing}(nothing), 2)
   └─ Document with text "One ". Metadata: (document_name = "a",)

julia> m.metadata
(query_name = "find one", corpus_name = "Numbers", document_name = "a")
```
"""
NamedQuery
