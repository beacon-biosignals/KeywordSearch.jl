using KeywordSearch, Test, UUIDs, Random
using Tables, StringDistances, Suppressor
using Aqua

# easier stateless testing of the global `KeywordSearch.AUTOMATIC_REPLACEMENTS`
# by emptying it, adding replacements, calling `f`, then restoring the former
# behavior.
function with_replacements(f, replaces...)
    former = copy(KeywordSearch.AUTOMATIC_REPLACEMENTS)
    empty!(KeywordSearch.AUTOMATIC_REPLACEMENTS)
    append!(KeywordSearch.AUTOMATIC_REPLACEMENTS, replaces)
    res = f()
    empty!(KeywordSearch.AUTOMATIC_REPLACEMENTS)
    append!(KeywordSearch.AUTOMATIC_REPLACEMENTS, former)
    return res
end

## Search robustness tests

@testset "Mistake 1: misspellings" begin
    @test match(FuzzyQuery("cobra"), Document("The cobre ate a mouse")) !== nothing
    @test match(FuzzyQuery("macaque"), Document("The macqaue ate a crab")) !== nothing
end

@testset "Mistake 2: word conjunctions" begin
    keyword = "ring-tailed lemur"
    text = "The ringtailed lemur sat in the sun."

    # This one matches just by the edit distance
    @test match(FuzzyQuery(keyword), Document(text)) !== nothing

    # It even matches exactly if we augment
    @test match(augment(Query(keyword)), Document(text)) !== nothing
end

@testset "Mistakes 3, 4: hyphenated words conjoined without hyphen or missing hyphen (with space)" begin
    keyword = "giant golden-crowned flying fox"
    # These match exactly due to removing punctuation in the documents
    for document_text in ("A giant golden crowned flying fox slept all day.",
         "A giant-golden-crowned flying fox slept all day.")
        @test match(Query(keyword), Document(document_text)) !== nothing
    end

    # These are 2 edits away, but appear to be 4 due to a possible bug
    for document_text in ("A giantgolden crowned flyingfox slept all day.",
         "A giantgolden crownedflying fox slept all day.")
        @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 1),
                    Document(document_text)) === nothing

        # https://github.com/matthieugomez/StringDistances.jl/issues/43
        @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 4),
                    Document(document_text)) !== nothing

        @test match(augment(Query(keyword)), Document(document_text)) !== nothing
        @test match(augment(FuzzyQuery(keyword)), Document(document_text)) !== nothing
    end

    # This one seems like 3 edits away, but since the same substring can't be edited more than once via the
    # "restricted edit distance" used by `DamerauLevenshtein()`, it comes out as 6 edits.
    document_text = "A giant goldencrownedflying fox slept all day."
    keyword = "giant golden-crowned flying fox"
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 1), Document(document_text)) ===
          nothing
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 2), Document(document_text)) ===
          nothing
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 6), Document(document_text)) !==
          nothing

    # document_text = "A giant goldencrownedflying fox slept all day."

    @test match(augment(Query(keyword)), Document(document_text)) !== nothing
    @test match(augment(FuzzyQuery(keyword)), Document(document_text)) !== nothing
end

@testset "Mistake 5: erroneously redacted terms" begin
    document = with_replacements("xxxs frog" => "Darwins frog") do
        return Document("""
        A xxxs frog sat on a branch.
        """)
    end
    @test match(Query("Darwins frog"), document) !== nothing
    @test match(Query("xxxs frog"), document) === nothing

    # Check call-side replacements
    document = Document("""
        A xxxs frog sat on a branch.
        """; replacements = ["xxxs frog" => "Darwins frog"])
    @test match(Query("Darwins frog"), document) !== nothing
    @test match(Query("xxxs frog"), document) === nothing

    @test Query("xxxs frog"; replacements = ["xxxs frog" => "Darwins frog"]).text == "Darwins frog"
    
end

@testset "Mistake 6: Search terms that are subsets of other general terms (like acrynoms)" begin
    @test match(Query(" ant "), Document("This matches ant here")) !== nothing
    @test match(Query(" ant "), Document("This does not match anteater here")) === nothing
    @test match(Query("ant"), Document("This does match anteater")) !== nothing

    @test match(word_boundary(Query("ant")), Document("This does match anteater")) ===
          nothing # part of a word is not OK
    @test match(word_boundary(Query("ant")), Document("This matches ant here")) !== nothing # a separate word is OK
    @test match(word_boundary(Query("ant")), Document("This matches ant")) !== nothing # end of string is OK
    @test match(word_boundary(Query("ant")), Document("This matches ant.")) !== nothing # period is OK
    @test match(word_boundary(Query("ant")), Document("This matches ant?")) !== nothing # other punctuation is OK

    # we count hyphens as a word boundary here (since we remove them from the documents and queries)
    @test match(word_boundary(Query("ant")), Document("This matches-ant")) !== nothing

    # Test that the first/last word in a document can be matched by a word boundary
    @test match(word_boundary(Query("abcd")), Document("abcd")) !== nothing
    @test match(word_boundary(Query("abcd")), Document("abcd hello")) !== nothing
    @test match(word_boundary(Query("abcd")), Document("hello abcd")) !== nothing
end

## A more representative test

@testset "Full query" begin
    # this is an actual query we are interested in
    query = augment(FuzzyQuery("leafcutting ant")) |
            augment(FuzzyQuery("leaf slicing ant")) |
            Query("ants") |
            Query("ant's") |
            Query(" ant ")

    # Note that the document has a hyphen and also a mispelling.
    # We still document a match because we replace hyphens with spaces,
    # and the extra `a` is within the threshold difference.
    document = Document("""The leaf-cutting aants walked around.""")
    @test match(query, document) !== nothing
    @test match(Query("ant's"), Document("The ant's exist")) !== nothing
    @test match(query, Document("The ant's exist")) !== nothing
    @test match(Query("ant's"), Document("The aant's exist")) !== nothing
    @test match(Query(" ant's "), Document("The aant's do not exist")) === nothing

    @test match(query, Document("This matches ant here")) !== nothing
    @test match(query, Document("This does not match anteater")) === nothing
end

## Functionality tests

# Some public domain text ("The Picture of Dorian Gray" by Oscar Wilde)
document = Document(lowercase("""
The artist is the creator of beautiful things.  To reveal art and
conceal the artist is art's aim.  The critic is he who can translate
into another manner or a new material his impression of beautiful
things.

The highest as the lowest form of criticism is a mode of autobiography.
Those who find ugly meanings in beautiful things are corrupt without
being charming.  This is a fault.

Those who find beautiful meanings in beautiful things are the
cultivated.  For these there is hope.  They are the elect to whom
beautiful things mean only beauty.

There is no such thing as a moral or an immoral book.  Books are well
written, or badly written.  That is all.

"""))

@testset "`Or`" begin
    has_artist = Query("artist")
    @test match(has_artist, document) !== nothing

    has_abc = Query("abc")
    @test match(has_abc, document) === nothing

    @test match(has_abc | has_artist, document) !== nothing
    @test length(has_abc | has_artist) == 2

    # test nesting
    query = (Query("a") | Query("b")) | (Query("c") | Query("d"))
    @test match(query, document) !== nothing
    @test query isa KeywordSearch.Or{Tuple{Query,Query,Query,Query}}
    @test length(query) == 4
end

@testset "`FuzzyQuery`" begin
    # Try some mispelling of "artist"
    fuzzy_has_altist = FuzzyQuery("altist", DamerauLevenshtein(), 1)
    @test match(fuzzy_has_altist, document) !== nothing

    fuzzy_has_atist = FuzzyQuery("atist", Levenshtein(), 1)
    @test match(fuzzy_has_atist, document) !== nothing
    @test match(Query("atist"), document) === nothing

    @test match(FuzzyQuery("atist", Levenshtein(), 0), document) === nothing
end

@testset "Match objects and `match_all`" begin
    document = Document("""The crab was eaten by a crb-eating macaque.""")
    query = FuzzyQuery("crab-eating macaque")

    m = match(query, document)
    @test m.query === query
    @test m.document === document
    @test m.distance == 2
    @test document.text[m.indices] == " crb eating macaque"

    matches = match_all(query, document)
    @test length(matches) == 1
    @test matches[1] == m

    query = FuzzyQuery("crab-eating macaque") | FuzzyQuery("crabeating macaque")
    matches = match_all(query, document)
    @test length(matches) == 2
    @test matches[1] == m

    @test matches[2].query == FuzzyQuery("crabeating macaque")
    @test matches[2].document === document
    @test matches[2].distance == 2
    @test document.text[matches[2].indices] == "crb eating macaque"
end

@testset "`match_all` for `Query`s" begin
    document = Document("""One crab was eaten.""")
    query = Query("One") | Query("crab") | Query("eat")
    matches = match_all(query, document)
    @test length(matches) == 3
    @test allunique(matches)
end

@testset "`_findmin` and `_findall`" begin
    ## Equal length cases

    # `d` replaced by `x`; 1 away
    str1 = "abcd"
    str2 = "abcx"
    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    @test d == Partial(DamerauLevenshtein(1))(str1, str2)
    @test matches == [(1, 1:4)] == [(d, inds)]
    @test KeywordSearch.non_overlapping_matches(matches) == matches

    # `cd` replaced by `xy`; 2 away
    str1 = "abcd"
    str2 = "abxy"

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    @test d == 2 # `max_dist + 1`
    @test isempty(matches)
    @test KeywordSearch.non_overlapping_matches(matches) == matches

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    @test d == Partial(DamerauLevenshtein(1))(str1, str2)
    @test matches == [(2, 1:4)] == [(d, inds)]
    @test KeywordSearch.non_overlapping_matches(matches) == matches

    ## Nonequal length cases

    # `d` replaced by `x`; 1 away
    str1 = "abcdef"
    str2 = "1234abcxef1234"

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    @test d == Partial(DamerauLevenshtein(1))(str1, str2)
    @test matches == [(1, 5:10)] == [(d, inds)]
    @test KeywordSearch.non_overlapping_matches(matches) == matches

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    @test d == Partial(DamerauLevenshtein(2))(str1, str2)
    @test matches == [(1, 5:10)] == [(d, inds)]
    @test KeywordSearch.non_overlapping_matches(matches) == matches

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    @test d == Partial(DamerauLevenshtein(3))(str1, str2)
    @test d == 1
    @test inds == 5:10
    @test matches == [(3, 4:9), (1, 5:10), (3, 6:11)]
    # all the matches overlap, so the following just chooses the best one):
    @test KeywordSearch.non_overlapping_matches(matches) == [(1, 5:10)]

    # `cde` replaced by `xyz`; 3 away
    str1 = "abcdef"
    str2 = "1234abxyzf1234"

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=1)
    @test d == Partial(DamerauLevenshtein(1))(str1, str2)
    @test d == 2 # max_dist + 1
    # not testing `inds` because they are undefined (since we hit `max_dist`)
    @test isempty(matches)

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=2)
    @test d == Partial(DamerauLevenshtein(2))(str1, str2)
    @test d == 3 # max_dist + 1
    # not testing `inds`
    @test isempty(matches)

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    @test d == Partial(DamerauLevenshtein(3))(str1, str2)
    @test matches == [(3, 5:10)] == [(d, inds)]

    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=4)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=4)
    @test d == Partial(DamerauLevenshtein(4))(str1, str2)
    @test matches == [(3, 5:10)] == [(d, inds)]

    # In the first case, `cde` replaced by `xyz` (3 away); in the second, only `e` is replaced by `x` (one away)
    str1 = "abcdef"
    str2 = "1234abxyzf1234abcdxf123"
    for max_dist in (1, 2)
        d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein());
                                         max_dist=max_dist)
        matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein());
                                         max_dist=max_dist)
        @test d == Partial(DamerauLevenshtein(max_dist))(str1, str2)
        @test matches == [(1, 15:20)] == [(d, inds)]
        @test KeywordSearch.non_overlapping_matches(matches) == matches
    end
    # Now at 3, we find the other match.
    # We also match at "4abcdx": delete '4', substitute 'x' => 'e', and insert 'f' at the end
    # as well as "bcdxf1": insert 'a' at the start, substitute 'x' => 'e', and delete '1' at the end
    d, inds = KeywordSearch._findmin(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    matches = KeywordSearch._findall(str1, str2, Partial(DamerauLevenshtein()); max_dist=3)
    @test d == Partial(DamerauLevenshtein(3))(str1, str2)
    @test (d, inds) == (1, 15:20)
    @test matches == [(3, 5:10), (3, 14:19), (1, 15:20), (3, 16:21)]
    # Now we have a somewhat interesting overlap removal: we have two "runs"
    # One is just `5:10` with no overlaps, so we keep that, and one with indices
    # ranging from `14` to `21`, and we keep the best one.
    @test KeywordSearch.non_overlapping_matches(matches) == [(3, 5:10), (1, 15:20)]
end

@testset "`Corpus` and `NamedMatch`" begin
    D1 = Document("There were crab eating macqaues!", (; document_uuid=uuid4()))
    D2 = Document("There were lobster eating macqaues!", (; document_uuid=uuid4()))
    C1 = Corpus([D1, D2], (; corpus_uuid=uuid4()))

    @test match(Query("lobster eating"), C1) !== nothing
    @test match(Query("lobster eating"), C1) == match(Query("lobster eating"), D2)
    @test match(Query("crab eating"), C1) !== nothing
    @test match(Query("crab eating"), C1) == match(Query("crab eating"), D1)
    @test match_all(Query("eating"), C1) ==
          [match(Query("eating"), D1), match(Query("eating"), D2)]

    eating_query = NamedQuery(Query("eating"), "eating query")
    matches = match_all(eating_query, C1)
    @test length(matches) == 2
    @test matches[1].metadata ==
          (; query_name="eating query", corpus_uuid=C1.metadata.corpus_uuid,
           document_uuid=D1.metadata.document_uuid)
    @test matches[2].metadata ==
          (; query_name="eating query", corpus_uuid=C1.metadata.corpus_uuid,
           document_uuid=D2.metadata.document_uuid)

    D1_matches = match_all(eating_query, D1)
    @test length(D1_matches) == 1
    @test D1_matches[1].metadata ==
          (; query_name="eating query", document_uuid=D1.metadata.document_uuid)
    @test D1_matches[1].match == matches[1].match

    D3 = Document("There were king cobras", (; document_uuid=uuid4()))
    d_uuid = uuid4()
    D4 = Document("There were other cobras", (; document_uuid=d_uuid))
    C2_uuid = uuid4()
    C2 = Corpus([D3, D4], (; corpus_uuid=C2_uuid))

    Q = NamedQuery(Query(" other"), "other")
    @test match(Q, C1) === nothing
    res = match(Q, C2)
    @test res isa KeywordSearch.NamedMatch
    @test res.metadata == (; query_name="other", corpus_uuid=C2_uuid, document_uuid=d_uuid)
    @test res.match == match(Q.query, D4)

    @test match(Q, D4).match == match(Q.query, D4)
    @test match(Q, D4).metadata == (; query_name="other", document_uuid=d_uuid)

    @testset "Tables interface for `NamedMatch`s" begin
        @test Tables.getcolumn(res, 1) == Tables.getcolumn(res, :query) == Q.query
        @test Tables.getcolumn(res, 2) == Tables.getcolumn(res, :document) == D4
        @test Tables.getcolumn(res, 3) == Tables.getcolumn(res, :distance) == 0
        @test Tables.getcolumn(res, 4) == Tables.getcolumn(res, :indices)
        @test Tables.getcolumn(res, 5) == Tables.getcolumn(res, :query_name) == "other"
        @test Tables.getcolumn(res, 6) == Tables.getcolumn(res, :corpus_uuid) == C2_uuid
        tbl = [res, res]
        @test Tables.isrowtable(tbl)
        @test Tables.columns(tbl).query_name == ["other", "other"]
        @test Tables.columnnames(res) ==
              (:document, :distance, :indices, :query, :query_name, :corpus_uuid,
               :document_uuid)
        @test sprint(explain, (first(Tables.rowtable(tbl)))) ===
              "The query \" other\" exactly matched the text \" There were other cobras \".\n"
    end
end

@testset "`AUTOMATIC_REPLACEMENTS`" begin
    @test with_replacements(() -> Document("abc"), "a" => "b") ==
          with_replacements(() -> Document("bbc"))
    @test Document("abc"; replacements=["a" => "b"]) == Document("bbc")

    @testset "Default replacements" begin
        @test Document("????hello??.???").text == " hello "
        @test Document("   hello     goodbye   ??").text == " hello goodbye "
        @test Document("   hello  !   goodbye   ??").text == " hello goodbye "
        @test Document("   hello   \n  goodbye   ??").text == " hello goodbye "
        @test Document("   hello \t\t  goodbye   ??").text == " hello goodbye "
        
        # Make sure we can match them too:
        @test match(Query("hello goodbye"), Document("   hello     goodbye   ??")) !== nothing
        @test match(Query("hello ??? goodbye"), Document("   hello     goodbye   ??")) !== nothing
        @test match(Query("hello   \t   \n goodbye"), Document("   hello     goodbye   ??")) !== nothing
    end
end

@testset "`Document` constructor start/end space" begin
    @test Document("hello").text == " hello "
    @test Document("hello ").text == " hello "
    @test Document(" hello").text == " hello "
    @test Document(" hello ").text == " hello "
end

## Edge cases

@testset "Query vs document lengths" begin
    for Q in (FuzzyQuery, Query)
        # Same query and document length
        @test match(Query("abc"), Document("def")) === nothing
        @test match(Query("abc"), Document("abc")) !== nothing
        @test length(match_all(Query("abc"), Document("abc"))) == 1
        @test length(match_all(Query("abc"), Document("def"))) == 0

        # Zero length query
        @test length(match_all(Query(""), Document("def"))) == 0
        @test match(Query(""), Document("def")) === nothing

        # Document length less than query length
        @test match(Query("abc"), Document("ab")) === nothing
        @test length(match_all(Query("abc"), Document("ab"))) == 0
    end
end

@testset "`text_left_endpoint` and `text_right_endpoint` unit tests" begin
    str = "OpuR5HEDQCWqrVNJHvwa" # from `randstring(20)`
    @test KeywordSearch.text_left_endpoint(str, 15; approx_length=20) == (1, "")
    @test KeywordSearch.text_left_endpoint(str, 15; approx_length=10) == (5, "…")

    @test KeywordSearch.text_right_endpoint(str, 5; approx_length=20) == (20, "")
    @test KeywordSearch.text_right_endpoint(str, 5; approx_length=10) == (15, "…")

    str_space = str[1:4] * " " * str[5:(end - 1)]
    @test KeywordSearch.text_left_endpoint(str_space, 15; approx_length=5) == (6, "…")
    @test KeywordSearch.text_left_endpoint(str_space, 15; approx_length=4) == (11, "…")

    @test KeywordSearch.text_right_endpoint(str_space, 1; approx_length=3) == (4, "…")
    @test KeywordSearch.text_right_endpoint(str_space, 1; approx_length=1) == (2, "…")
end

@testset "Errors" begin
    # Cannot use `match` as a metadata key
    @test_throws ArgumentError Document("abc", (; match=1))
    @test_throws ArgumentError Corpus([Document("abc")], (; match=1))
    @test_throws ArgumentError NamedQuery(Query("abc"), (; match=1))

    # Cannot have the same metadata keys in a corpus and a document it contains
    @test_throws ErrorException Corpus([Document("abc", (; uuid=uuid4()))],
                                       (; uuid=uuid4()))

    # Cannot have the same metadata keys in a `NamedQuery` and an object it is matched to
    @test_throws ErrorException match(NamedQuery(Query("a"), (; uuid=uuid4())),
                                      Document("abc", (; uuid=uuid4())))
    @test_throws ErrorException match(NamedQuery(Query("a"), (; uuid=uuid4())),
                                      Corpus([Document("abc", (; uuid=uuid4()))],
                                             (; corpus_name="a")))
end

@testset "Aqua tests" begin
    Aqua.test_all(KeywordSearch)
end
