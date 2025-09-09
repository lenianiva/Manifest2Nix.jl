import Pkg
using Pkg.API: PackageInfo
using Base: UUID

function to_pinned_manifest(id::UUID, info::PackageInfo)::Dict
    return Dict()
end

function load_dependencies(output_path::String)
    dependencies = Pkg.dependencies()
    for (k, v) in dependencies
        println("$(v.name): [$k] $(v.git_source)@$(v.git_revision)")
    end
end

load_dependencies("hi")
