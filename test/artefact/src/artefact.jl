module artefact

using Pkg.Artifacts

rootpath = artifact"socrates"
open(joinpath(rootpath, "bin", "socrates")) do file
    println(read(file, String))
end

end # module artefact
