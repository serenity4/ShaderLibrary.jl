using ShaderLibrary
using Documenter

DocMeta.setdocmeta!(ShaderLibrary, :DocTestSetup, :(using ShaderLibrary); recursive=true)

makedocs(;
    modules=[ShaderLibrary],
    authors="Cédric BELMANT",
    repo="https://github.com/serenity4/ShaderLibrary.jl/blob/{commit}{path}#{line}",
    sitename="ShaderLibrary.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://serenity4.github.io/ShaderLibrary.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/serenity4/ShaderLibrary.jl",
    devbranch="main",
)
