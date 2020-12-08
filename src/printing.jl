# Printing using `AbstractTrees.print_tree`
# I implemented this for Convex.jl and it seemed nice, so let's try it here too.

# A simple wrapper to stop `AbstractTrees.children` from recursing 
struct NoChildren
    x::Any
end
Base.show(io::IO, n::NoChildren) = show(io, n.x)

AbstractTrees.children(q::NamedQuery) = (NoChildren(q.metadata), q.query)
AbstractTrees.children(q::NamedMatch) = (NoChildren(q.metadata), q.match)

AbstractTrees.children(q::QueryMatch) = (q.query, q.haystack)

AbstractTrees.children(q::Or) = q.subqueries
AbstractTrees.children(q::And) = q.subqueries
AbstractTrees.children(q::Query) = tuple()
AbstractTrees.children(q::FuzzyQuery) = tuple()

AbstractTrees.printnode(io::IO, q::Or) = print(io, "Or")
AbstractTrees.printnode(io::IO, q::And) = print(io, "And")
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

Base.show(io::IO, q::Union{And,Or,NamedQuery,NamedMatch}) = print_tree_rstrip(io, q)

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

function Base.show(io::IO, R::Document)
    n, rdots = text_right_endpoint(R.text)

    show_full_text = (length(R.text) < 15) || rdots == ""
    if show_full_text
        print(io, "Document with text ")
        show(io, R.text)
    else
        print(io, "Document starting with ")
        print(io, "\"", R.text[1:n], rdots, "\"")
    end
    print(io, ". Metadata: ")
    show(io, R.metadata)
    return nothing
end

function Base.show(io::IO, P::Corpus{T,TR}) where {T,TR}
    compact = get(io, :compact, false)
    print(io, "Corpus with ", length(P.documents), " documents, each with metadata keys: ")
    print(io, _nt_names(TR))

    if !compact
        print(io, "\nCorpus metadata: ", P.metadata)
    end
end

function printcontext(io::IO, m::QueryMatch; context=40)
    text = m.haystack.text
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

explain(m::AbstractMatch; context=40) = explain(stdout, m; context=context)

function Base.show(io::IO, m::QueryMatch)
    return print(io, "QueryMatch with distance ", m.distance, " at indices ", m.indices, ".")
end
