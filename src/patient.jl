struct Patient{T<:NamedTuple,TR}
    reports::Vector{Report{TR}}
    metadata::T

    function Patient(reports::Vector{Report{TR}}, metadata::T) where {T,TR}
        disjoint_keys_check(T, TR)
        check_keys(T)

        return new{T,TR}(reports, metadata)
    end
end

function Base.match(query::AbstractQuery, p::Patient)
    for r in p.reports
        m = match(query, r)
        if m !== nothing
            return m
        end
    end
    return nothing
end

function match_all(query::AbstractQuery, p::Patient)
    return reduce(vcat, (match_all(query, report) for report in p.reports))
end
