# Named queries

```@repl 2
using KeywordSearch, Random, DataFrames

queries = [NamedQuery(FuzzyQuery("dog"), "find dog"),
           NamedQuery(FuzzyQuery("cat"), "find cat"),
           NamedQuery(Query("koala") | FuzzyQuery("Opossum"), "find marsupial")]

words = ["dg", "cat", "koala", "opposum"]
corpus1 = Corpus([Document(randstring(rand(1:10)) * rand(words) * randstring(rand(1:10)),
                           (; doc_index=j)) for j in 1:10], (; name="docs"))

corpus1.documents

corpus2 = Corpus([Document(randstring(rand(1:10)), (; doc_index=2 * j)) for j in 1:10],
                 (; name="other docs"))

corpuses = [corpus1, corpus2]

matches = [match(named_query, corpus) for named_query in queries for corpus in corpuses];
filter!(!isnothing, matches);
DataFrame(matches)
```

We can also make use of [Transducers.jl](https://github.com/JuliaFolds/Transducers.jl) to easily
multithread or parallelize across cores via `tcollect` or `dcollect`:

```@repl 2
using Transducers
matches = tcollect(Filter(!isnothing)(MapSplat(match)(Iterators.product(queries, corpuses))));
DataFrame(matches)
```
