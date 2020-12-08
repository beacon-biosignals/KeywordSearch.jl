using KeywordSearch
using Documenter

makedocs(; modules=[KeywordSearch], sitename="KeywordSearch",
         authors="Beacon Biosignals and other contributors",
         pages=["Home" => "index.md",
                "Quick tutorial" => "tutorial.md",
                "Tables of queries" => "named_queries.md",
                "API Documentation" => "api_documentation.md"],
         )

deploydocs(; repo="github.com/beacon-biosignals/KeywordSearch.jl.git", devbranch="main",
           push_preview=true)
