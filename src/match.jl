abstract type AbstractMatch end

struct QueryMatch{Q,H,D,I} <: AbstractMatch
    query::Q
    haystack::H
    distance::D
    indices::I
end

# We make a new object instead of using an array or tuple of
# `QueryMatch`'s directly, since semantically an `AndMatch`
# is a new object, a single match to an `And` query that consists
# of a match for each query that is being `And`'d together.
struct AndMatch{Q} <: AbstractMatch
    matches::Q
end
