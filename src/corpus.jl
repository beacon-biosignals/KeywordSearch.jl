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
