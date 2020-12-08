# format

Run `julia --project=format format/run.jl` with Julia 1.5 to run JuliaFormatter.

If you update Julia or the version of JuliaFormatter, make sure to also update
`.github/workflows/format_check.yml` to match. This ensures that the same code
is used to format as is used for the verification check.
