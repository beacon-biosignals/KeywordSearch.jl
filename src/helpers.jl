"""
    augment(term) -> Vector{String}

Given a term, returns a list of terms which should be treated as synonyms.
Currently only supports agumenting (spaces or hyphens) with (spaces, no spaces).

## Example

```julia
julia> KeywordSearch.augment("arctic wolf")
2-element Array{String,1}:
 "arctic wolf"
 "arcticwolf"
 
```
"""
function augment(term)
    terms = String[]
    words = split(term, char -> isspace(char) || char == '-')
    n_words = length(words)
    joiners = (" ", "")
    # This could be optimized
    for joins in Iterators.product(Iterators.repeated(joiners, n_words - 1)...)
        word = ""
        for (w, j) in zip(words, joins)
            word = string(word, w, j)
        end
        word = string(word, words[end])
        push!(terms, word)
    end
    return terms
end

reconstruct(Q::FuzzyQuery) = x -> FuzzyQuery(x, Q.dist, Q.threshold)
reconstruct(Q::Query) = Query

function augment(Q::AbstractQuery)
    make_q = reconstruct(Q)
    return Or(Tuple(make_q.(augment(Q.text))))
end

"""
    word_boundary(Q::AbstractQuery) -> AbstractQuery

Ensures that a word or phrase is not hyphenated or conjoined with the surrounding text.

## Examples

```julia
using KeywordSearch, Test, UUIDs
query = Query("word")
@test match(query, Report("This matchesword ", uuid4())) !== nothing
@test match(word_boundary(query), Report("This matches word.", uuid4())) !== nothing
@test match(word_boundary(query), Report("This matches word ", uuid4())) !== nothing
@test match(word_boundary(query), Report("This matches word\nNext line", uuid4())) !== nothing
@test match(word_boundary(query), Report("This doesn't matchword ", uuid4())) === nothing
```
"""
function word_boundary(Q::AbstractQuery)
    # `process_report` has removed punctuation, so we just need to check for spaces.
    make_q = reconstruct(Q)
    stripped_text = strip(Q.text)
    return make_q(string(" ", stripped_text, " "))
end

Base.length(Q::AbstractQuery) = mapreduce(x -> 1, +, AbstractTrees.Leaves(Q); init=0)

function check_keys(::Type{T}) where {T<:NamedTuple}
    if :match ∈ _nt_names(T)
        throw(ArgumentError("Must not include `match` as a metadata key."))
    end
    return nothing
end

function disjoint_keys_check(::NamedQuery{T1}, ::Patient{T2,TR}) where {T1,T2,TR}
    disjoint_keys_check(T1, T2)
    disjoint_keys_check(T1, TR)
    return nothing
end

function disjoint_keys_check(::NamedQuery{T1}, ::Report{T2}) where {T1,T2}
    disjoint_keys_check(T1, T2)
    return nothing
end

# a similar version of this exists as an internal function in Base:
# https://github.com/JuliaLang/julia/blob/e68dda9785b4523cae49f8a60f99aa9360226eb4/base/namedtuple.jl#L181
_nt_names(::Type{NamedTuple{names,T}}) where {names,T} = names

function disjoint_keys_check(::Type{T1}, ::Type{T2}) where {T1,T2}
    if !isdisjoint(_nt_names(T1), _nt_names(T2))
        error("Metadata keys will clash when merging metadata to construct the `NamedMatch`.")
    end
    return nothing
end
