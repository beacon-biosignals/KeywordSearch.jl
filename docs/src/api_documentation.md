# API Documentation

```@meta
CurrentModule = KeywordSearch
```

## Queries

```@docs
Query
FuzzyQuery
NamedQuery
```

## Documents
```@docs
Document
match(::AbstractQuery, ::Document)
match_all(::AbstractQuery, ::Document)
```

## Corpuses

```@docs
Corpus
match(::AbstractQuery, ::Corpus)
match_all(::AbstractQuery, ::Corpus)
```

## Matches

```@docs
QueryMatch
NamedMatch
```

## Helper functions

```@docs
explain
augment
word_boundary
```

## Constants

```@docs
AUTOMATIC_REPLACEMENTS
```
