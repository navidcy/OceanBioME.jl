pushfirst!(LOAD_PATH, joinpath(@__DIR__, "..")) # add OceanBioME to environment stack

using Documenter, DocumenterCitations, Literate, Glob

using OceanBioME
using OceanBioME.SLatissimaModel: SLatissima
using OceanBioME.LOBSTERModel: LOBSTER
using OceanBioME.Boundaries.Sediments: SimpleMultiG

bib_filepath = joinpath(dirname(@__FILE__), "oceanbiome.bib")
bib = CitationBibliography(bib_filepath)

# Examples

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const OUTPUT_DIR   = joinpath(@__DIR__, "src/generated")

examples = [
    "box.jl",
    "column.jl",
    "data_forced.jl",
    "kelp.jl",
    "eady.jl"
]

function replace_silly_warning(content)
    content = replace(content, r"┌ Warning:.*\s+└ @ JLD2 ~/\.julia/packages/JLD2/.*/reconstructing_datatypes\.jl.*\n" => "")
    return content
end

for example in examples
    example_filepath = joinpath(EXAMPLES_DIR, example)

    withenv("JULIA_DEBUG" => "Literate") do
        Literate.markdown(example_filepath, OUTPUT_DIR; 
                          flavor = Literate.DocumenterFlavor(), 
                          repo_root_url="https://oceanbiome.github.io/OceanBioME.jl", 
                          execute=true,
                          postprocess=replace_silly_warning)
    end
end

example_pages = [
    "Simple column model" => "generated/column.md",
    "Data forced column model" => "generated/data_forced.md",
    "Model with particles (kelp) interacting with the biogeochemistry" => "generated/kelp.md",
    "Box model" => "generated/box.md",
    "Baroclinical instability" => "generated/eady.md"]

bgc_pages = [
    "Overview" => "model_components/biogeochemical/index.md",
    "LOBSTER" => "model_components/biogeochemical/LOBSTER.md",
    "NPZD" => "model_components/biogeochemical/NPZ.md"
]

sed_pages = [
    "Overview" => "model_components/sediment.md",
]

individuals_pages = [
    "Overview" => "model_components/individuals/index.md",
    "Sugar Kelp (Broch and Slagstad 2012 ++)" => "model_components/individuals/slatissima.md",
]

component_pages = [
    "Biogeochemical models" => bgc_pages,
    "Air-sea gas exchange" => "model_components/air-sea-gas.md",
    "Sediment models" => sed_pages,
    "Light attenuation models" => "model_components/light.md",
    "Individuals" => individuals_pages,
    "Utilities" => "model_components/utils.md"
]

numerical_pages = [
    "Positivity preservation" => "numerical_implementation/positivity-preservation.md"
]


param_pages = [
    "Overview" => "appendix/params/index.md",
    "LOBSTER" => "appendix/params/LOBSTER.md",
    "SLatissima" => "appendix/params/SLatissima.md"
]

appendix_pages = [
    "Library" => "appendix/library.md",
    "Function index" => "appendix/function_index.md",
    "Parameters" => param_pages
]

pages = [
    "Home" => "index.md",
    "Quick start" => "quick_start.md",
    "Model components and setup" => component_pages,
    "Examples" => example_pages,
    "Numerical implementation" => numerical_pages,
    "Gallery" => "gallery.md",
    "References" => "references.md",
    "Appendix" => appendix_pages
]

#####
##### Build and deploy docs
#####

format = Documenter.HTML(
    collapselevel = 1,
    prettyurls = get(ENV, "CI", nothing) == "true",
    canonical = "https://OceanBioME.github.io/OceanBioME/stable/",
    mathengine = MathJax3(),
)

makedocs(bib,
    sitename = "OceanBioME.jl",
    authors = "Jago Strong-Wrigt, John R. Taylor, and Si Chen",
    format = format,
    pages = pages,
    modules = Module[OceanBioME],
    doctest = false,#true,
    strict = false,#true,
    clean = true,
    checkdocs = :exports
)

@info "Cleaning up temporary .jld2 and .nc files created by doctests..."

for file in vcat(glob("docs/*.jld2"), glob("docs/*.nc"))
    rm(file)
end

deploydocs(
          repo = "github.com/OceanBioME/OceanBioME.jl",
          forcepush = true,
          push_preview = true,
          devbranch = "main"
)

