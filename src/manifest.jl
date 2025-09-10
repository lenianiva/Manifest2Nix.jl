module Manifest

import Pkg
import TOML
using Pkg.API: PackageInfo
using Base: UUID, @kwdef

@kwdef struct PinnedManifest
    uuid::UUID
    dependencies::Vector{String}
    is_tracking_registry::Bool
end

function to_pinned_manifest(uuid::UUID, info::PackageInfo)::PinnedManifest
    return PinnedManifest(
        uuid=uuid,
        is_tracking_registry=info.is_tracking_registry,
        dependencies=collect(keys(info.dependencies)),
    )
end

format(nothing) = "null"
format(x::PinnedManifest) = Dict(
    "uuid" => x.uuid,
    "is_tracking_registry" => x.is_tracking_registry,
    "dependencies" => x.dependencies
)
format(u::UUID) = string(u)

function load_dependencies(; path_output::Union{Some{String}, Nothing}=nothing)
    dependencies = Pkg.dependencies()
    payload = Dict(
        v.name => to_pinned_manifest(k, v)
        for (k, v) in dependencies
    )
    project_info = Pkg.project()
    result = Dict(
        "name" => project_info.name,
        "uuid" => project_info.uuid,
        "deps" => payload,
    )

    writer = io::IO -> TOML.print(format, io, result)
    if isnothing(path_output)
        writer(stdout)
    else
        open(writer, path_output, "w")
    end
end

end
