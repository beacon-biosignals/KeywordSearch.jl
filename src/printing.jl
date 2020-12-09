# Printing using `AbstractTrees.print_tree`
# I implemented this for Convex.jl and it seemed nice, so let's try it here too.

# A simple wrapper to stop `AbstractTrees.children` from recursing 
struct NoChildren
    x::Any
end
Base.show(io::IO, n::NoChildren) = show(io, n.x)

AbstractTrees.children(q::NamedQuery) = (NoChildren(q.metadata), q.query)
AbstractTrees.children(q::NamedMatch) = (NoChildren(q.metadata), q.match)

AbstractTrees.children(q::QueryMatch) = (q.query, q.document)

AbstractTrees.children(q::Or) = q.subqueries
AbstractTrees.children(q::Query) = tuple()
AbstractTrees.children(q::FuzzyQuery) = tuple()

AbstractTrees.printnode(io::IO, q::Or) = print(io, "Or")
AbstractTrees.printnode(io::IO, q::NamedQuery) = print(io, "NamedQuery")
AbstractTrees.printnode(io::IO, q::NamedMatch) = print(io, "NamedMatch")

# Don't show all those types
function AbstractTrees.printnode(io::IO, q::FuzzyQuery)
    print(io, "FuzzyQuery(")
    show(io, q.text)
    print(io, ", ", q.dist, ", ", q.threshold, ")")
    return nothing
end

function print_tree_rstrip(io::IO, x)
    str = sprint(AbstractTrees.print_tree, x)
    print(io, rstrip(str))
    return nothing
end

"""
    Base.show(io::IO, q::Union{Or,NamedQuery,NamedMatch})

[`Or`]@(ref), [`NamedQuery`](@ref), and [`NamedMatch`](@ref) are
pretty-printed as trees.

## Example

```jldoctest
julia> q = Query("a") | Query("b")
Or
├─ Query("a")
└─ Query("b")

julia> named = NamedQuery(q, "is it a or is it b?")
NamedQuery
├─ (query_name = "is it a or is it b?",)
└─ Or
   ├─ Query("a")
   └─ Query("b")

julia> match(named, Document("It is a!"))
NamedMatch
├─ (query_name = "is it a or is it b?",)
└─ QueryMatch with distance 0 at indices 7:7.
   ├─ Query("a")
   └─ Document with text "It is a  ". Metadata: NamedTuple()

```
"""
Base.show(io::IO, q::Union{Or,NamedQuery,NamedMatch}) = print_tree_rstrip(io, q)

# `text_left_endpoint` and `text_right_endpoint` could be combined
# but it would probably be too clever... let's just duplicate it

function text_left_endpoint(text::AbstractString, start=1; approx_length=15)
    L = max(prevind(text, start, approx_length), firstindex(text))

    if L == firstindex(text)
        return L, ""
    end

    # Not at the start, so look for a word break
    space_inds = findprev(" ", text, L)

    if space_inds !== nothing
        L_space = nextind(text, last(space_inds))

        # make sure we don't have to go too far to get to the space
        if start - L_space <= 2 * approx_length
            L = L_space
        end
    end

    return L, "…"
end

function text_right_endpoint(text::AbstractString, start=1; approx_length=15)
    R = min(nextind(text, start, approx_length), lastindex(text))

    if R == lastindex(text)
        return R, ""
    end

    space_inds = findnext(" ", text, R)

    if space_inds !== nothing
        R_space = prevind(text, first(space_inds))
        if R_space - start <= 2 * approx_length
            R = R_space
        end
    end

    return R, "…"
end

"""
    Base.show(io::IO, D::Document)

Pretty-prints a [`Document`](@ref).

# Example

```jldoctest
julia> Document("Doc 1", (; doc_idx = 1)) # short documents print completely
Document with text "Doc 1 ". Metadata: (doc_idx = 1,)

julia> Document("This is a longer document! Lots of words here.", (; doc_idx = 1)) # longer documents print truncated
Document starting with "This is a longer…". Metadata: (doc_idx = 1,)

```
"""
function Base.show(io::IO, D::Document)
    n, rdots = text_right_endpoint(D.text)

    show_full_text = (length(D.text) < 15) || rdots == ""
    if show_full_text
        print(io, "Document with text ")
        show(io, D.text)
    else
        print(io, "Document starting with ")
        print(io, "\"", D.text[1:n], rdots, "\"")
    end
    print(io, ". Metadata: ")
    show(io, D.metadata)
    return nothing
end

"""
    Base.show(io::IO, C::Corpus)

Pretty-prints a [`Corpus`](@ref).

## Example

```jldoctest
julia> C1 = Corpus([Document("Doc 1", (; doc_idx = 1)), Document("Doc 2", (; doc_idx = 2))], (; name = "Lots of docs"))
Corpus with 2 documents, each with metadata keys: (:doc_idx,)
Corpus metadata: (name = "Lots of docs",)

julia> C2 = Corpus([Document("a")], (; a = 1));

julia> [C1, C2]
2-element Array{Corpus,1}:
 Corpus with 2 documents, each with metadata keys: (:doc_idx,)
 Corpus with 1 documents, each with metadata keys: ()

```
"""
function Base.show(io::IO, C::Corpus{T,TR}) where {T,TR}
    print(io, "Corpus with ", length(C.documents), " documents, each with metadata keys: ")
    print(io, _nt_names(TR))
    return nothing
end

function Base.show(io::IO, ::MIME"text/plain", C::Corpus{T,TR}) where {T,TR}
    show(io, C)
    print(io, "\nCorpus metadata: ", C.metadata)
    return nothing
end

function printcontext(io::IO, m::QueryMatch; context=40)
    text = m.document.text
    L, ldots = text_left_endpoint(text, first(m.indices); approx_length=context)
    R, rdots = text_right_endpoint(text, last(m.indices); approx_length=context)

    LL = prevind(text, first(m.indices))
    RR = nextind(text, last(m.indices))
    print(io, ldots)
    if LL > L
        print(io, replace(text[L:LL], "\n" => "\\n"))
    end
    printstyled(io, text[m.indices]; bold=true)
    if RR < R
        print(io, replace(text[RR:R], "\n" => "\\n"))
    end
    print(io, rdots)
    return nothing
end

# `raw` due to escaped quotes in `sprint(explain...)`
@doc raw"""
    explain([io=stdout], match; context=40)

Prints a human-readable explanation of the match
and its context in the document in which it was found.

## Example

```jldoctest
julia> document = Document("The crabeating macacue ate a crab.")
Document starting with "The crabeating macacue…". Metadata: NamedTuple()

julia> query = augment(FuzzyQuery("crab-eating macaque"))
Or
├─ FuzzyQuery("crab eating macaque", DamerauLevenshtein{Nothing}(nothing), 2)
├─ FuzzyQuery("crabeating macaque", DamerauLevenshtein{Nothing}(nothing), 2)
├─ FuzzyQuery("crab eatingmacaque", DamerauLevenshtein{Nothing}(nothing), 2)
└─ FuzzyQuery("crabeatingmacaque", DamerauLevenshtein{Nothing}(nothing), 2)

julia> m = match(query, document)
QueryMatch with distance 1 at indices 5:22.

julia> explain(m)
The query "crabeating macaque" matched the text "The crabeating macacue ate a crab  " with distance 1.

julia> explain(m; context=5) # tweak the amount of context printed
The query "crabeating macaque" matched the text "The crabeating macacue ate…" with distance 1.

julia> sprint(explain, m) # to get the explanation as a string
"The query \\"crabeating macaque\\" matched the text \\"The crabeating macacue ate a crab  \\" with distance 1.\n"

julia> explain(match(Query("crab"), document)) # exact queries print slightly differently
The query "crab" exactly matched the text "The crabeating macacue ate a crab  ".

julia> explain(match(NamedQuery(Query("crab"), "crab query"), document)) # `NamedQuery`s print the same as their underlying query
The query "crab" exactly matched the text "The crabeating macacue ate a crab  ".

```
"""
explain

function explain(io::IO, m::QueryMatch{<:FuzzyQuery}; context=40)
    print(io, "The query ")
    show(io, m.query.text)
    print(io, " matched the text \"")
    printcontext(io, m; context=context)
    print(io, "\" with distance ", m.distance, ".\n")
    return nothing
end

function explain(io::IO, m::QueryMatch{Query}; context=40)
    print(io, "The query ")
    show(io, m.query.text)
    print(io, " exactly matched the text \"")
    printcontext(io, m; context=context)
    print(io, "\".\n")
    return nothing
end

# in case we no longer have a `QueryMatch` but at least have a row-like
# object with the right fields.
function explain(io::IO, row; context=40)
    match = QueryMatch(row.query, row.document, row.distance, row.indices)
    return explain(io, match; context=context)
end

explain(m; context=40) = explain(stdout, m; context=context)

"""
    Base.show(io::IO, m::QueryMatch)

Pretty-prints a [`QueryMatch`](@ref).

## Example

```jldoctest
julia> match(Query("claws"), Document("Lemurs have nails instead of claws."))
QueryMatch with distance 0 at indices 30:34.

```
"""
function Base.show(io::IO, m::QueryMatch)
    return print(io, "QueryMatch with distance ", m.distance, " at indices ", m.indices,
                 ".")
end
