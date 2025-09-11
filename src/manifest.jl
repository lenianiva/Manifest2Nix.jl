module Manifest

import Pkg
import TOML
using Pkg.API: PackageInfo
using Pkg.Types: Context
using Base: UUID, SHA1, @kwdef

@kwdef struct PinnedPackage
    uuid::UUID
    version::VersionNumber
    dependencies::Vector{String}
    repo::String
    rev::SHA1
end

function pin_package(context::Context, uuid::UUID, info::PackageInfo)::Union{PinnedPackage, Nothing}
    if Pkg.Types.is_stdlib(uuid, VERSION)
        #@assert !haskey(context.registries[1], uuid)
        return nothing
    elseif info.is_tracking_path
        error("Cannot pin a package $(info.name) [$uuid] tracking a path. Please supply the package explicitly with a derivation.")
    elseif info.is_tracking_registry
        pkg_entry = get(context.registries[1], uuid, nothing)
        if isnothing(pkg_entry)
            error("Package $(info.name) [$uuid] is not present in any registry")
        end
        Pkg.Registry.init_package_info!(pkg_entry)
        repo = pkg_entry.info.repo
        rev = pkg_entry.info.version_info[info.version].git_tree_sha1
    elseif info.is_tracking_repo
        repo = info.git_source
        rev = info.git_revision
    else
        error("Package $(info.name) [$uuid] is not tracking a registry and not tracking a repo")
    end
    return PinnedPackage(
        uuid=uuid,
        version=info.version,
        dependencies=collect(keys(info.dependencies)),
        repo=repo,
        rev=rev,
    )
end

format(nothing) = "null"
format(x::PinnedPackage) = Dict(
    "uuid" => x.uuid,
    "version" => x.version,
    "dependencies" => x.dependencies,
    "repo" => x.repo,
    "rev" => x.rev,
)
format(u::UUID) = string(u)

function load_dependencies(context; path_output::Union{Some{String}, Nothing}=nothing)
    @assert length(context.registries) == 1
    dependencies = Pkg.dependencies(context.env)
    @info "Pinning $(length(dependencies)) dependencies"
    pinned_dependencies = Dict()
    for (uuid, info) in dependencies
        pinned = pin_package(context, uuid, info)
        if isnothing(pinned)
            continue
        end
        pinned_dependencies[info.name] = pinned
    end
    project_info = Pkg.project(context.env)

    result = Dict(
        "name" => context.env.project.name,#project_info.name,
        "uuid" => project_info.uuid,
        "deps" => pinned_dependencies,
    )

    @info "Generating Lock File"
    writer = io::IO -> TOML.print(format, io, result)
    if isnothing(path_output)
        writer(stdout)
    else
        open(writer, path_output, "w")
    end
end

end
