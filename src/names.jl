struct NamedMatch{T,M<:AbstractMatch} <: AbstractMatch
    match::M
    metadata::T
    function NamedMatch(match::M, metadata::T) where {M,T}
        check_keys(T)
        return new{T,M}(match, metadata)
    end
end

Tables.getcolumn(m::NamedMatch, i::Int) = i == 1 ? m.match : m.metadata[i - 1]
Tables.getcolumn(m::NamedMatch, s::Symbol) = s === :match ? m.match : m.metadata[s]
Tables.columnnames(m::NamedMatch) = (:match, keys(m.metadata)...)
Tables.isrowtable(::Type{<:AbstractVector{<:NamedMatch}}) = true

explain(io::IO, m::NamedMatch; context=40) = explain(io, m.match; context=context)

"""
    NamedMatch

This object has two fields, `match` and `metadata`, and is created by
the method `match(query::NamedQuery, obj)`. `NamedMatch` satisfies the
Tables.jl `AbstractRow` interface. This means that a vector of `NamedMatch`
objects is a valid Tables.jl-compatible table.
"""
NamedMatch

struct NamedQuery{T<:NamedTuple,Q<:AbstractQuery} <: AbstractQuery
    query::Q
    metadata::T

    function NamedQuery(query::Q, metadata::T) where {T,Q}
        check_keys(T)
        return new{T,Q}(query, metadata)
    end
end

NamedQuery(query::AbstractQuery, name::AbstractString) = NamedQuery(query, (; query_name=name))

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
end

"""
    NamedQuery(metadata::Union{String, NamedTuple}, query::AbstractQuery)

Creates a `NamedQuery` that stores a metadata field holding information
about the query. When used with `match`, returns a [`NamedMatch`](@ref), which
carries the metadata of the `NamedQuery` as well as the metadata of the
object which was matched.

## Example

```julia
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
└─ FuzzyQuery("one", DamerauLevenshtein(), 2)

julia> m = match(query, corpus)
NamedMatch
├─ (query_name = "find one", corpus_name = "Numbers", document_name = "a")
└─ QueryMatch with distance 1 at indices 1:3.
   ├─ FuzzyQuery("one", DamerauLevenshtein(), 2)
   └─ Document with text "One ". Metadata: (document_name = "a",)

julia> m.metadata
(query_name = "find one", corpus_name = "Numbers", document_name = "a")
```
"""
NamedQuery
