using Quantica
using Documenter

makedocs(;
    modules=[Quantica],
    authors="Pablo San-Jose",
    repo="https://github.com/pablosanjose/Quantica.jl/blob/{commit}{path}#L{line}",
    sitename="Quantica.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://pablosanjose.github.io/Quantica.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/pablosanjose/Quantica.jl",
)