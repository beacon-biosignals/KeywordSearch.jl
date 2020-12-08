# Quick tutorial

In this example, we will use some sample text modified from the public domain text *Aristotle's History of Animals* <http://www.gutenberg.org/files/59058/59058-0.txt>.

```@repl 1
using KeywordSearch, Random

text_with_typos = Document("""
    Some animals have fet, others have noone; of the former some have
    two feet, as mankind and birdsonly; others have four, as the lizard
    and the dog; others, as the scolopendra and bee, have many feet; but
    all have their feet in pairs.
    """) 

fuzzy_query = FuzzyQuery("birds only")

m = match(fuzzy_query, text_with_typos)

explain(m)
```

Here, you'll notice an exact query does not match, since the words "birds" and "only" have been conjoined:

```@repl 1
exact_query = Query("birds only")

match(exact_query, text_with_typos) # nothing, no exact match
```

KeywordSearch offers the [`augment`](@ref) function specifically to address mis-conjoined words:
```@repl 1
augmented_query = augment(exact_query)

m2 = match(augmented_query, text_with_typos) # now it matches

m2.query # which of the two queries in the `Or` matched?
```

Here, `augment` generated an `Or` query, but we can generate one ourselves:
```@repl 1
dog_or_cat = Query("dog") | Query("cat")

m3 = match(dog_or_cat, text_with_typos)

explain(m3)
```

Note also that [`FuzzyQuery`](@ref) by default uses the `DamerauLevenshtein()` distance from [StringDistances.jl](https://github.com/matthieugomez/StringDistances.jl), and searches for a match within a cutoff of 2 but you can pass it another distance or use another cutoff:


```@repl 1
fuzzy_query_2 = FuzzyQuery("brid nly", DamerauLevenshtein(), 4)
m4 = match(fuzzy_query_2, text_with_typos) 
explain(m4)
```
