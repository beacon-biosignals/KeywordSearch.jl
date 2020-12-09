# run this script in the `docs` project to fix the doctests if they are out of date
# carefully review the changes before committing!

using Documenter, KeywordSearch

DocMeta.setdocmeta!(KeywordSearch, :DocTestSetup, :(using KeywordSearch); recursive=true)

if success(`git diff --quiet`)
    doctest(KeywordSearch, fix=true)
else
    error("Git repo dirty; commit changes before fixing doctests.")
end
