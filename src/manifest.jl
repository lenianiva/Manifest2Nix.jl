module Manifest

import Pkg
import TOML
using Git: git
using Pkg.API: PackageInfo
using Pkg.Types: Context
using Base: UUID, SHA1, @kwdef

@kwdef struct PinnedPackage
    uuid::UUID
    version::VersionNumber
    dependencies::Vector{String}
    repo::String
    rev::String
end

function pin_package(
    context::Context,
    uuid::UUID,
    info::PackageInfo,
)::Union{PinnedPackage,Nothing}
    if Pkg.Types.is_stdlib(uuid, VERSION)
        @info "Skipping stdlib package $(info.name) [$uuid]"
        #@assert !haskey(context.registries[1], uuid)
        return nothing
    elseif info.is_tracking_path
        error(
            "Cannot pin a package $(info.name) [$uuid] tracking a path. Please supply the package explicitly with a derivation.",
        )
    elseif info.is_tracking_registry
        pkg_entry = get(context.registries[1], uuid, nothing)
        if isnothing(pkg_entry)
            error("Package $(info.name) [$uuid] is not present in any registry")
        end
        Pkg.Registry.init_package_info!(pkg_entry)
        repo = pkg_entry.info.repo
        rev_tag = readchomp(git(["ls-remote", repo, "v$(info.version)"]))
        rev = split(rev_tag, "\t"; limit = 2)[1]
    elseif info.is_tracking_repo
        repo = info.git_source
        rev = info.git_revision
        @assert rev isa string
    else
        error(
            "Package $(info.name) [$uuid] is not tracking a registry and not tracking a repo",
        )
    end
    return PinnedPackage(
        uuid = uuid,
        version = info.version,
        dependencies = collect(keys(info.dependencies)),
        repo = repo,
        rev = rev,
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
format(other::VersionNumber) = string(other)

function load_dependencies(
    context;
    path_project::String,
    path_output::Union{String,Nothing} = nothing,
)
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
        path_output = "$path_project/Lock.toml"
    end

    if path_output == "-"
        writer(stdout)
    else
        open(writer, path_output, "w")
    end
end

function main(args::Dict{String,Any})
    path_project = args["project"]
    Pkg.Operations.with_temp_env(path_project) do
        @info "Creating context for project $path_project"
        context = Pkg.Types.Context()

        Pkg.instantiate()

        @info "Processing dependencies for project $(context.env.project.name)"
        Manifest.load_dependencies(
            context;
            path_project = path_project,
            path_output = get(args, "output", nothing),
        )
    end
end

end
