# `@doc` needed for using a `raw` string as a docstring; raw needed because
# of the escape characters in the regex.
@doc raw"""
    Document{T<:NamedTuple}

Represents a single string document. This object has two fields,

* `text::String`
* `metadata::T`

The `text` is automatically processed by applying the replacements
from [`AUTOMATIC_REPLACEMENTS`](@ref) and
adding a space to the end of the document.
"""
struct Document{T<:NamedTuple}
    text::String
    metadata::T

    function Document(text::AbstractString, metadata::T) where {T}
        check_keys(T)

        # Add a final space to ensure that the last word is recognized
        # as a word boundary.
        new_text = apply_replacements(text) * " "
        return new{T}(new_text, metadata)
    end
end

Document(text::AbstractString) = Document(text, NamedTuple())

function apply_replacements(str::AbstractString)
    # Apply automatic replacements
    # using https://github.com/JuliaLang/julia/issues/29849#issuecomment-449535743
    return foldl(replace, AUTOMATIC_REPLACEMENTS; init=str)
end

abstract type AbstractQuery end

"""
    QueryMatch{Q<:AbstractQuery,Doc<:Document,D,I}

Represents a match for an `AbstractQuery`, with four fields:

* `query::Q`: the query itself
* `document::Doc`: the [`Document`](@ref) which was matched to
* `distance::D`: the distance of the match
* `indices::I`: the indices of where in the `document` the match occurred.

"""
struct QueryMatch{Q<:AbstractQuery,Doc<:Document,D,I}
    query::Q
    document::Doc
    distance::D
    indices::I
end

"""
    Query <: AbstractQuery

A query to search for an exact match of a string,
with one field:

* `text::String`

The `text` is automatically processed by applying the replacements
from [`AUTOMATIC_REPLACEMENTS`](@ref).
"""
struct Query <: AbstractQuery
    text::String
    Query(str::AbstractString) = new(apply_replacements(str))
end

"""
    Base.match(query::AbstractQuery, document::Document)

Looks for a match for `query` in `document`. Returns either `nothing`
if no match is found, or a [`QueryMatch`](@ref) object.
"""
Base.match(query::AbstractQuery, document::Document)

"""
    match_all(query::AbstractQuery, document::Document)

Looks for all matches for `query` in the document. Returns a
`Vector` `QueryMatch` objects corresponding to all of the matches found.
"""
match_all(query::AbstractQuery, document::Document)

function Base.match(Q::Query, R::Document)
    if (length(R.text) < length(Q.text)) || (length(Q.text) == 0)
        return nothing
    end
    inds = findfirst(Q.text, R.text)
    inds === nothing && return nothing
    return QueryMatch(Q, R, 0, inds)
end

function match_all(Q::Query, R::Document)
    if (length(R.text) < length(Q.text)) || (length(Q.text) == 0)
        all_inds = UnitRange[]
    else
        all_inds = findall(Q.text, R.text)
        if all_inds === nothing
            all_inds = UnitRange[]
        end
    end
    return [QueryMatch(Q, R, 0, inds) for inds in all_inds]
end

struct Or{S<:Tuple} <: AbstractQuery
    subqueries::S
end

function Base.match(Q::Or, R::Document)
    for subquery in Q.subqueries
        m = match(subquery, R)
        m !== nothing && return m
    end
    return nothing
end

function match_all(Q::Or, R::Document)
    return reduce(vcat, (match_all(subquery, R) for subquery in Q.subqueries))
end

# Specializations to combine Or's
function Or(q1::Or, q2::AbstractQuery)
    return Or((q1.subqueries..., q2))
end

Or(q1::AbstractQuery, q2::Or) = Or(q2, q1)

function Or(q1::Or, q2::Or)
    return Or((q1.subqueries..., q2.subqueries...))
end

Or(q1::AbstractQuery, q2::AbstractQuery) = Or((q1, q2))

Base.:(|)(q1::AbstractQuery, q2::AbstractQuery) = Or(q1, q2)

"""
    FuzzyQuery{D,T} <: AbstractQuery

A query to search for an fuzzy match of a string,
with three fields:

* `text::String`: the text to match
* `dist::D`: the distance measure to use; defaults to `DamerauLevenshtein()`
* `threshold::T`: the maximum threshold allowed for a match; defaults to 2.

The `text` is automatically processed by applying the replacements
from [`AUTOMATIC_REPLACEMENTS`](@ref).
"""
struct FuzzyQuery{D,T} <: AbstractQuery
    text::String
    dist::D
    threshold::T
    function FuzzyQuery(str::AbstractString, dist::D, threshold::T) where {D,T}
        return new{D,T}(apply_replacements(str), dist, threshold)
    end
end

FuzzyQuery(str::String) = FuzzyQuery(str, DamerauLevenshtein(), 2)

function dist_with_threshold(dist::DamerauLevenshtein, str1, str2, max_dist)
    return DamerauLevenshtein(max_dist)(str1, str2)
end

function dist_with_threshold(dist::Levenshtein, str1, str2, max_dist)
    return Levenshtein(max_dist)(str1, str2)
end

# Maybe to be upstreamed?
# https://github.com/matthieugomez/StringDistances.jl/issues/29

"""
    _findmin(s1, s2, dist::Partial; max_dist) -> d, inds

StringDistances' `Partial(dist)(s1, s2, max_dist)` returns
the value `d`, the closest partial match between the two strings, up to a maximum
distance `max_dist` (if no match is found less than `max_dist`, then
`max_dist+1` is returned). `_findmin` returns the same value, but also
returns the first set of indices at which an optimal partial match was found.
"""
function _findmin(s1, s2, dist::Partial; max_dist)
    s1, s2 = StringDistances.reorder(s1, s2)
    len1, len2 = length(s1), length(s2)
    len1 == len2 && return dist_with_threshold(dist.dist, s1, s2, max_dist),
           firstindex(s2):lastindex(s2)
    out = max_dist + 1
    len1 == 0 && return out, 1:0
    out_idx = 0
    for (i, x) in enumerate(qgrams(s2, len1))
        curr = dist_with_threshold(dist.dist, s1, x, max_dist)
        out_idx = ifelse(curr < out, i, out_idx)
        out = min(out, curr)
        max_dist = min(out, max_dist)
    end
    return out, nextind(s2, 0, out_idx):nextind(s2, 0, out_idx + len1 - 1)
end

function Base.match(Q::FuzzyQuery, R::Document)
    # We assume the document text is longer than the query text
    length(R.text) < length(Q.text) && return nothing

    dist, inds = _findmin(Q.text, R.text, Partial(Q.dist); max_dist=Q.threshold)
    return dist <= Q.threshold ? QueryMatch(Q, R, dist, inds) : nothing
end

"""
    _findall(s1, s2, dist::Partial; max_dist) -> Vector{Tuple{Int,UnitRange}}

Returns all of the matches within `max_dist` found by `dist`, returning tuples
of the distance along with the indices of the match.
"""
function _findall(s1, s2, dist::Partial; max_dist)
    s1, s2 = StringDistances.reorder(s1, s2)
    len1, len2 = length(s1), length(s2)
    matches = Tuple{Int,UnitRange}[]

    len1 == 0 && return matches

    if len1 == len2
        curr = dist_with_threshold(dist.dist, s1, s2, max_dist)
        if curr <= max_dist
            push!(matches, (curr, firstindex(s2):lastindex(s2)))
        end
        return matches
    end

    for (i, x) in enumerate(qgrams(s2, len1))
        curr = dist_with_threshold(dist.dist, s1, x, max_dist)
        if curr <= max_dist
            inds = nextind(s2, 0, i):nextind(s2, 0, i + len1 - 1)
            push!(matches, (curr, inds))
        end
    end
    return matches
end

# This takes as input all matches and partitions them into runs
# of overlapping matches. Then chooses the best match from each run.
# Let's say there are matches at 1:3, 2:3, 2:4, 4:5 and 6:7
# Then we only have 2 runs, one involving indices 1:5 and one from 6:7
# Note that 1:3 and 4:5 do not intersect, yet they are in the same run.
# (A math way to say this is that we choose the best representative from the equivalence class of connected components).
# Why do it this way? Well, it's the best I thought of so far.
# Another way would be to say "two matches are the same if they share > 50% of the same indices".
# That seems slightly more reasonable (avoding the situation in the example above where 1:3 and 4:5 have no overlap)
# But it's actually hard to do sensibly, since you have have say 1:3, 2:4, 3:5 and 4:6. Then 1:3 and 2:4 share 2 indices,
# and 2:4 and 3:5 share two indices, and 3:5 and 4:6 share two indices. So which do you keep? Could resolve them one at at time left-to-right
# but then you're actually doing the same thing as the "run of connected components" except requiring a 50% overlap and can run into
# the same issue where you discard disconnected matches. For exmaple what if 4:6 is the best match followed by 3:5 then 2:4?
# Then you have 1:3 and 2:4, keep 2:4. Then you have 2:4 and 3:5, keep 3:5. Then
# you have 3:5 and 4:6, keep 4:6. Now we've just chosen the best match from all of them, but didn't keep 1:3 even though it has no overlap with 4:6.
function non_overlapping_matches(matches)
    length(matches) <= 1 && return matches
    non_overlapping_matches = Tuple{Int,UnitRange}[]
    best_curr_match = first(matches)
    inds_so_far = best_curr_match[2]
    for m in matches
        dist, inds = m
        if first(inds) <= last(inds_so_far)
            inds_so_far = first(inds_so_far):last(inds)
            if dist < best_curr_match[1]
                best_curr_match = m
            end
        else
            push!(non_overlapping_matches, best_curr_match)
            best_curr_match = m
            inds_so_far = inds
        end
    end
    push!(non_overlapping_matches, best_curr_match)
    return non_overlapping_matches
end

function match_all(Q::FuzzyQuery, R::Document)
    matches = _findall(Q.text, R.text, Partial(Q.dist); max_dist=Q.threshold)
    matches_no_overlap = non_overlapping_matches(matches)
    return [QueryMatch(Q, R, m...) for m in matches_no_overlap]
end
