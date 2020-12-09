"""
    Corpus{T<:NamedTuple,D}

A corpus is a collection of [`Document`](@ref)s, along with some metadata. It has two fields,

* `documents::Vector{Document{D}}` 
* `metadata::T`

Note each `Document` in a `Corpus` must have metadata of the same type.
"""
struct Corpus{T<:NamedTuple,D}
    documents::Vector{Document{D}}
    metadata::T

    function Corpus(documents::Vector{Document{D}}, metadata::T) where {T,D}
        disjoint_keys_check(T, D)
        check_keys(T)

        return new{T,D}(documents, metadata)
    end
end

function Base.match(query::AbstractQuery, p::Corpus)
    for r in p.documents
        m = match(query, r)
        if m !== nothing
            return m
        end
    end
    return nothing
end

function match_all(query::AbstractQuery, p::Corpus)
    return reduce(vcat, (match_all(query, document) for document in p.documents))
end

"""
    Base.match(query::AbstractQuery, corpus::Corpus)

Looks for a match for `query` in any [`Document`](@ref) in `corpus`.
Returns either `nothing` if no match is found in any `Document`,
or a [`QueryMatch`](@ref) object.
"""
Base.match(query::AbstractQuery, corpus::Corpus)

"""
    match_all(query::AbstractQuery, corpus::Corpus)

Looks for all matches for `query` from all documents in `corpus`. Returns a
`Vector` of `QueryMatch` objects corresponding to all of the matches found,
across all doucments.
"""
match_all(query::AbstractQuery, corpus::Corpus)
