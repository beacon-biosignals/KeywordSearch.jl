using KeywordSearch, Test, UUIDs, Random
using Tables, StringDistances, Suppressor

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
    @test match(FuzzyQuery("cobra"), Report("The cobre ate a mouse")) !== nothing
    @test match(FuzzyQuery("macaque"), Report("The macqaue ate a crab")) !== nothing
end

@testset "Mistake 2: word conjunctions" begin
    keyword = "ring-tailed lemur"
    text = "The ringtailed lemur sat in the sun."

    # This one matches just by the edit distance
    @test match(FuzzyQuery(keyword),
                Report(text)) !== nothing

    # It even matches exactly if we augment
    @test match(augment(Query(keyword)),
                Report(text)) !== nothing
end

@testset "Mistakes 3, 4: hyphenated words conjoined without hyphen or missing hyphen (with space)" begin
    keyword = "giant golden-crowned flying fox"
    # These match exactly due to removing punctuation in the reports
    for report_text in
        ("A giant golden crowned flying fox slept all day.", "A giant-golden-crowned flying fox slept all day.")
        @test match(Query(keyword), Report(report_text)) !== nothing
    end

    # These are 2 edits away, but appear to be 4 due to a possible bug
    for report_text in
        ("A giantgolden crowned flyingfox slept all day.", "A giantgolden crownedflying fox slept all day.")
        @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 1),
                    Report(report_text)) === nothing

        # https://github.com/matthieugomez/StringDistances.jl/issues/43
        @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 4),
                    Report(report_text)) !== nothing

        @test match(augment(Query(keyword)), Report(report_text)) !== nothing
        @test match(augment(FuzzyQuery(keyword)), Report(report_text)) !==
              nothing
    end

    # This one seems like 3 edits away, but since the same substring can't be edited more than once via the
    # "restricted edit distance" used by `DamerauLevenshtein()`, it comes out as 6 edits.
    report_text = "A giant goldencrownedflying fox slept all day."
    keyword = "giant golden-crowned flying fox"
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 1),
                Report(report_text)) === nothing
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 2),
                Report(report_text)) === nothing
    @test match(FuzzyQuery(keyword, DamerauLevenshtein(), 6),
                Report(report_text)) !== nothing

    # report_text = "A giant goldencrownedflying fox slept all day."

    @test match(augment(Query(keyword)), Report(report_text)) !== nothing
    @test match(augment(FuzzyQuery(keyword)), Report(report_text)) !== nothing
end

@testset "Mistake 5: erroneously redacted terms" begin
    report = with_replacements("xxxs frog" => "Darwins frog") do
        return Report("""
        A xxxs frog sat on a branch.
        """)
    end
    @test match(Query("Darwins frog"), report) !== nothing
    @test match(Query("xxxs frog"), report) === nothing
end

@testset "Mistake 6: Search terms that are subsets of other general terms (like acrynoms)" begin
    @test match(Query(" ant "), Report("This matches ant here")) !== nothing
    @test match(Query(" ant "), Report("This does not match anteater here")) === nothing
    @test match(Query("ant"), Report("This does match anteater")) !== nothing

    @test match(word_boundary(Query("ant")), Report("This does match anteater")) === nothing # part of a word is not OK
    @test match(word_boundary(Query("ant")), Report("This matches ant here")) !== nothing # a separate word is OK
    @test match(word_boundary(Query("ant")), Report("This matches ant")) !== nothing # end of string is OK
    @test match(word_boundary(Query("ant")), Report("This matches ant.")) !== nothing # period is OK
    @test match(word_boundary(Query("ant")), Report("This matches ant?")) !== nothing # other punctuation is OK

    # we count hyphens as a word boundary here (since we remove them from the reports and queries)
    @test match(word_boundary(Query("ant")), Report("This matches-ant")) !== nothing
end

## A more representative test

@testset "Full query" begin
    # this is an actual query we are interested in
    query = augment(FuzzyQuery("leafcutting ant")) |
            augment(FuzzyQuery("leaf slicing ant")) |
            Query("ants") |
            Query("ant's") |
            Query(" ant ")

    # Note that the report has a hyphen and also a mispelling.
    # We still report a match because we replace hyphens with spaces,
    # and the extra `a` is within the threshold difference.
    report = Report("""The leaf-cutting aants walked around.""")
    @test match(query, report) !== nothing
    @test match(Query("ant's"), Report("The ant's exist")) !== nothing
    @test match(query, Report("The ant's exist")) !== nothing
    @test match(Query("ant's"), Report("The aant's exist")) !== nothing
    @test match(Query(" ant's "), Report("The aant's do not exist")) === nothing

    @test match(query, Report("This matches ant here")) !== nothing
    @test match(query, Report("This does not match anteater")) === nothing
end

## Functionality tests

# Some public domain text ("The Picture of Dorian Gray" by Oscar Wilde)
report = Report(lowercase("""
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

@testset "`And` and `Or`" begin
    has_artist = Query("artist")
    @test match(has_artist, report) !== nothing

    has_abc = Query("abc")
    @test match(has_abc, report) === nothing

    @test match(has_abc | has_artist, report) !== nothing
    @test length(has_abc | has_artist) == 2

    @test match(has_abc & has_artist, report) === nothing
    @test length(has_abc & has_artist) == 2

    ands = Query("a") & Query("r") & Query("t") & Query("i")
    @test length(ands) == 4

    # Test that we collapse instead of nesting
    @test ands isa KeywordSearch.And{NTuple{4,Query}}
    @test match(ands, report) !== nothing

    query = (Query("a") | Query("b")) & (Query("c") & Query("d"))
    @test match(query, report) !== nothing
    @test query isa
          KeywordSearch.And{Tuple{KeywordSearch.Or{Tuple{Query,Query}},Query,Query}}
    @test length(query) == 4

    query = (Query("a") & Query("b")) & (Query("c") | Query("d"))
    @test length(query) == 4
    @test match(query, report) !== nothing
    @test query isa
          KeywordSearch.And{Tuple{Query,Query,KeywordSearch.Or{Tuple{Query,Query}}}}
end

@testset "`FuzzyQuery`" begin
    # Try some mispelling of "artist"
    fuzzy_has_altist = FuzzyQuery("altist", DamerauLevenshtein(), 1)
    @test match(fuzzy_has_altist, report) !== nothing

    fuzzy_has_atist = FuzzyQuery("atist", Levenshtein(), 1)
    @test match(fuzzy_has_atist, report) !== nothing
    @test match(Query("atist"), report) === nothing

    @test match(FuzzyQuery("atist", Levenshtein(), 0), report) === nothing
end

@testset "Match objects and `match_all`" begin
    report = Report("""The crab was eaten by a crb-eating macaque.""")
    query = FuzzyQuery("crab-eating macaque")

    m = match(query, report)
    @test m.query === query
    @test m.haystack === report
    @test m.distance == 2
    @test report.text[m.indices] == " crb eating macaque"

    matches = match_all(query, report)
    @test length(matches) == 1
    @test matches[1] == m

    query = FuzzyQuery("crab-eating macaque") | FuzzyQuery("crabeating macaque")
    matches = match_all(query, report)
    @test length(matches) == 2
    @test matches[1] == m

    @test matches[2].query == FuzzyQuery("crabeating macaque")
    @test matches[2].haystack === report
    @test matches[2].distance == 2
    @test report.text[matches[2].indices] == "crb eating macaque"
end

@testset "`match_all` for `Query`s" begin
    report = Report("""One crab was eaten.""")
    query = Query("One") | Query("crab") | Query("eat")
    matches = match_all(query, report)
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

@testset "Printing and `explain`" begin
    report = Report("Short.")
    @test occursin("Report with text", sprint(show, report))

    report = Report("""Two crabs were eaten. This is a longer report
                        with line breaks and everything. Blah blah blah.""")
    @test occursin("starting with", sprint(show, report))
    @test occursin("eaten…", sprint(show, report))

    patient = Patient([report, report], (;))
    @test occursin("with 2 reports, each with metadata keys", sprint(show, patient))
    @test occursin("Patient metadata:", sprint(show, patient))

    # test that long reports without spaces are still truncated
    @test occursin("…\".", sprint(show, Report(randstring(50))))

    DL = sprint(show, DamerauLevenshtein())
    @test sprint(show, FuzzyQuery("crab") | Query("eat")) == """
        Or
        ├─ FuzzyQuery("crab", $DL, 2)
        └─ Query("eat")"""

    @test sprint(show, FuzzyQuery("crab") & Query("eat")) == """
        And
        ├─ FuzzyQuery("crab", $DL, 2)
        └─ Query("eat")"""

    @test sprint(show, FuzzyQuery("crab") & (Query("eat") | Query("a"))) == """
       And
       ├─ FuzzyQuery("crab", $DL, 2)
       └─ Or
          ├─ Query("eat")
          └─ Query("a")"""

    m = match(FuzzyQuery("crab"), report)
    answer = "The query \"crab\" matched the text \"Two crabs were eaten  This is a longer report\\nwith…\" with distance 0.\n"
    @test sprint(explain, m) == answer
    @test @capture_out(explain(m)) == answer
    
    @test sprint((io, x) -> explain(io, x; context=20), m) ==
        "The query \"crab\" matched the text \"Two crabs were eaten  This is…\" with distance 0.\n"

    Q = Query("crab")
    m = match(Q, report)
    @test sprint(explain, m) ==
        "The query \"crab\" exactly matched the text \"Two crabs were eaten  This is a longer report\\nwith…\".\n"
    @test sprint((io, x) -> explain(io, x; context=20), m) ==
        "The query \"crab\" exactly matched the text \"Two crabs were eaten  This is…\".\n"

    named_query = NamedQuery(Q, "name")
    @test sprint(show, named_query) == """
        NamedQuery
        ├─ (query_name = "name",)
        └─ Query("crab")"""

    named_match = match(named_query, report)
    @test sprint(explain, named_match) == sprint(explain, m)

    @test sprint(show, named_match) == """
        NamedMatch
        ├─ (query_name = "name",)
        └─ QueryMatch with distance 0 at indices 5:8.
           ├─ Query("crab")
           └─ Report starting with "Two crabs were eaten…". Metadata: NamedTuple()"""
end

@testset "`Patient` and `NamedMatch`" begin
    R1 = Report("There were crab eating macqaues!", (; report_uuid=uuid4()))
    R2 = Report("There were lobster eating macqaues!", (; report_uuid=uuid4()))
    P1 = Patient([R1, R2], (; patient_uuid=uuid4()))

    @test match(Query("lobster eating"), P1) !== nothing
    @test match(Query("lobster eating"), P1) == match(Query("lobster eating"), R2)
    @test match(Query("crab eating"), P1) !== nothing
    @test match(Query("crab eating"), P1) == match(Query("crab eating"), R1)
    @test match_all(Query("eating"), P1) ==
          [match(Query("eating"), R1), match(Query("eating"), R2)]

    R3 = Report("There were king cobras", (; report_uuid=uuid4()))
    d_uuid = uuid4()
    R4 = Report("There were other cobras", (; report_uuid=d_uuid))
    P2_uuid = uuid4()
    P2 = Patient([R3, R4], (; patient_uuid=P2_uuid))

    Q = NamedQuery(Query(" other"), "other")
    @test match(Q, P1) === nothing
    res = match(Q, P2)
    @test res isa KeywordSearch.NamedMatch
    @test res.metadata ==
          (; query_name="other", patient_uuid=P2_uuid, report_uuid=d_uuid)
    @test res.match == match(Q.query, R4)

    @test match(Q, R4).match == match(Q.query, R4)
    @test match(Q, R4).metadata == (; query_name="other", report_uuid=d_uuid)

    @testset "Tables interface for `NamedMatch`s" begin
        tbl = [res, res]
        @test Tables.getcolumn(res, 2) == "other"
        @test Tables.isrowtable(tbl)
        @test Tables.columns(tbl).query_name == ["other", "other"]
        @test Tables.columnnames(res) == (:match, :query_name, :patient_uuid, :report_uuid)
    end
end

@testset "`AUTOMATIC_REPLACEMENTS`" begin
    @test with_replacements(() -> Report("abc"), "a" => "b") == with_replacements(() -> Report("bbc"))
end

## Edge cases

@testset "Query vs report lengths" begin
    for Q in (FuzzyQuery, Query)
        # Same query and report length
        @test match(Query("abc"), Report("def")) === nothing
        @test match(Query("abc"), Report("abc")) !== nothing
        @test length(match_all(Query("abc"), Report("abc"))) == 1
        @test length(match_all(Query("abc"), Report("def"))) == 0

        # Zero length query
        @test length(match_all(Query(""), Report("def"))) == 0
        @test match(Query(""), Report("def")) === nothing

        # Report length less than query length
        @test match(Query("abc"), Report("ab")) === nothing
        @test length(match_all(Query("abc"), Report("ab"))) == 0
    end
end

@testset "`text_left_endpoint` and `text_right_endpoint` unit tests" begin
    str = "OpuR5HEDQCWqrVNJHvwa" # from `randstring(20)`
    @test KeywordSearch.text_left_endpoint(str, 15; approx_length=20) == (1, "")
    @test KeywordSearch.text_left_endpoint(str, 15; approx_length=10) == (5, "…")

    @test KeywordSearch.text_right_endpoint(str, 5; approx_length=20) == (20, "")
    @test KeywordSearch.text_right_endpoint(str, 5; approx_length=10) == (15, "…")

    str_space = str[1:4] * " " * str[5:end-1]
    @test KeywordSearch.text_left_endpoint(str_space, 15; approx_length=5) == (6, "…")
    @test KeywordSearch.text_left_endpoint(str_space, 15; approx_length=4) == (11, "…")

    @test KeywordSearch.text_right_endpoint(str_space, 1; approx_length=3) == (4, "…")
    @test KeywordSearch.text_right_endpoint(str_space, 1; approx_length=1) == (2, "…")

end

@testset "Errors" begin
    # Cannot use `match` as a metadata key
    @test_throws ArgumentError Report("abc", (; match=1))
    @test_throws ArgumentError Patient([Report("abc")], (; match=1))
    @test_throws ArgumentError NamedQuery(Query("abc"), (; match=1))

    # Cannot have the same metadata keys in a patient and a report it contains
    @test_throws ErrorException Patient([Report("abc", (; uuid=uuid4()))], (; uuid=uuid4()))

    # Cannot have the same metadata keys in a `NamedQuery` and an object it is matched to
    @test_throws ErrorException match(NamedQuery(Query("a"), (; uuid=uuid4())),
                                      Report("abc", (; uuid=uuid4())))
    @test_throws ErrorException match(NamedQuery(Query("a"), (; uuid=uuid4())),
                                      Patient([Report("abc", (; uuid=uuid4()))],
                                              (; patient_name="a")))
end
