module Manifest

import Pkg
import TOML
using Git: git
using Pkg.API: PackageInfo
using Pkg.Types: Context
using Base: UUID, SHA1, Filesystem, @kwdef

@kwdef struct PinnedPackage
    uuid::UUID
    version::VersionNumber
    dependencies::Vector{String}
    repo::Union{Nothing,String}
    rev::Union{Nothing,String}
    subdir::Union{Nothing,String}
end

function pin_package(
    context::Context,
    uuid::UUID,
    info::PackageInfo;
    temp_dir::String,
)::Union{PinnedPackage,Nothing}
    subdir = nothing
    if Pkg.Types.is_stdlib(uuid, VERSION)
        @info "Skipping stdlib package $(info.name) [$uuid]"
        return nothing
    elseif info.is_tracking_path
        repo = info.git_source
        rev = info.git_revision
        @warn "A package $(info.name) [$uuid] is tracking a path. Please supply the package explicitly with a derivation."
    elseif info.is_tracking_registry
        pkg_entry = get(context.registries[1], uuid, nothing)
        if isnothing(pkg_entry)
            error("Package $(info.name) [$uuid] is not present in any registry")
        end
        Pkg.Registry.init_package_info!(pkg_entry)
        repo = pkg_entry.info.repo
        subdir = pkg_entry.info.subdir
        @info "Processing package $(info.name) [$uuid] (tracking registry repo $repo)"
        if info.tree_hash == ""
            error("Package does not have a tree hash")
        end

        # Calculate revision from tree hash

        repo_dir = "$temp_dir/$(info.name)"
        run(`$git clone --quiet --filter=blob:none --no-checkout $repo $repo_dir`)
        if isnothing(subdir)
            rev_tag = readchomp(
                pipeline(
                    Cmd(`$git log --pretty=raw --all`, dir = repo_dir),
                    `grep -B 1 $(info.tree_hash)`,
                    `head -1`,
                ),
            )
            rev = split(rev_tag, " "; limit = 2)[2]
        else
            all_commits = split(readchomp(Cmd(`$git rev-list HEAD`, dir = repo_dir)), "\n")
            # Find commit with hash
            for commit_hash in all_commits
                hash = readchomp(Cmd(`$git rev-parse $commit_hash:$subdir`, dir = repo_dir))
                if hash == info.tree_hash
                    rev = commit_hash
                    break
                end
            end
        end

        if rev == ""
            error(
                "Could not determine revision using either tag or tree hash $(info.version)",
            )
        end
    elseif info.is_tracking_repo
        repo = info.git_source
        rev = info.git_revision
        if rev == ""
            error("Package $(info.name) [$uuid] (tracking repo) has an empty revision")
        end
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
        subdir = subdir,
    )
end

format(nothing) = ""
format(x::PinnedPackage) = Dict(
    "uuid" => x.uuid,
    "version" => x.version,
    "dependencies" => x.dependencies,
    "repo" => x.repo,
    "rev" => x.rev,
    "subdir" => x.subdir,
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
    temp_dir = Filesystem.mktempdir()
    pinned_dependencies = Dict()
    for (uuid, info) in dependencies
        pinned = pin_package(context, uuid, info; temp_dir)
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
        if args["up"]
            Pkg.API.up(context)
        end

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
