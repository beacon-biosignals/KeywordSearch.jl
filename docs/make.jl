using KeywordSearch
using Documenter

makedocs(modules=[KeywordSearch],
         sitename="KeywordSearch",
         authors="Beacon Biosignals and other contributors",
         pages=["API Documentation" => "index.md"],
         )

       
deploydocs(repo="github.com/beacon-biosignals/KeywordSearch.jl.git",
           devbranch="main",
           push_preview=true)
