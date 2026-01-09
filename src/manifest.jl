module Manifest

import Pkg
import TOML, JSON
using Git: git
using Pkg.API: PackageInfo
using Pkg.Types: Context
using Base: UUID, SHA1, Filesystem, @kwdef

@kwdef struct PinnedPackage
    uuid::UUID
    version::Union{Nothing,VersionNumber}
    repo::Union{Nothing,String}
    rev::Union{Nothing,String}
    subdir::Union{Nothing,String}
    hash::Union{Nothing,String}
    tree_hash::Union{Nothing,String}
end

function tree_hash_to_commit_hash(
    repo::String,
    subdir::Union{Nothing,String},
    info::PackageInfo,
    temp_dir::String;
    rev::String = "HEAD",
)::String
    repo_dir = "$temp_dir/$(info.name)"
    run(`$git clone --quiet --filter=blob:none --no-checkout $repo $repo_dir`)
    commit_hash = ""
    if isnothing(subdir)
        rev_tag = readchomp(
            pipeline(
                Cmd(`$git log --pretty=raw --all`, dir = repo_dir),
                `grep -B 1 $(info.tree_hash)`,
                `head -1`,
            ),
        )
        commit_hash = split(rev_tag, " "; limit = 2)[2]
    else
        all_commits = split(readchomp(Cmd(`$git rev-list $rev`, dir = repo_dir)), "\n")
        # Find commit with hash
        for commit in all_commits
            hash = readchomp(Cmd(`$git rev-parse $commit:$subdir`, dir = repo_dir))
            if hash == info.tree_hash
                commit_hash = commit
                break
            end
        end
    end

    if commit_hash == ""
        error("Could not determine revision using either tag or tree hash $(info.version)")
    end
    return commit_hash
end

function pin_package(
    context::Context,
    uuid::UUID,
    info::PackageInfo;
    temp_dir::String,
    existing::Union{PinnedPackage,Nothing},
)::Union{PinnedPackage,Nothing}
    subdir = nothing
    hash = nothing
    tree_hash = nothing
    if Pkg.Types.is_stdlib(uuid, VERSION)
        @info "stdlib package $(info.name) [$uuid]"
        repo = nothing
        rev = nothing
    elseif info.is_tracking_path
        repo = info.git_source
        rev = info.git_revision
        @warn "A package $(info.name) [$uuid] is tracking a path. Please supply the package explicitly with a derivation."
    elseif info.is_tracking_registry
        if !isnothing(existing) && info.tree_hash == existing.tree_hash
            @info "Package $(info.name) [$uuid] not updated"
            return existing
        end
        tree_hash = info.tree_hash
        pkg_entry = get(context.registries[1], uuid, nothing)
        if isnothing(pkg_entry)
            error("Package $(info.name) [$uuid] is not present in any registry")
        end
        Pkg.Registry.init_package_info!(pkg_entry)
        repo = pkg_entry.info.repo
        subdir = pkg_entry.info.subdir
        @info "Source: $(info.source)"
        @info "Processing package $(info.name) [$uuid] (tracking registry repo $repo)"
        if info.tree_hash == ""
            error("Package does not have a tree hash")
        end

        rev = tree_hash_to_commit_hash(repo, subdir, info, temp_dir)
    elseif info.is_tracking_repo
        repo = info.git_source
        rev = info.git_revision
        if !isnothing(existing) && rev == existing.rev
            @info "Package $(info.name) [$uuid] not updated"
            return existing
        end
        entry = context.env.manifest.deps[uuid]
        rev = tree_hash_to_commit_hash(repo, entry.repo.subdir, info, temp_dir; rev = rev)
        if rev == ""
            error("Package $(info.name) [$uuid] (tracking repo) has an empty revision")
        end
    else
        error(
            "Package $(info.name) [$uuid] is not tracking a registry and not tracking a repo",
        )
    end
    if !isnothing(repo)
        prefetch = readchomp(
            `nix flake prefetch --extra-experimental-features 'nix-command flakes' --json git+$repo\?allRefs=1\&ref=$rev`,
        )
        prefetch = JSON.parse(prefetch)
        hash = prefetch["hash"]
    end
    return PinnedPackage(
        uuid = uuid,
        version = info.version,
        repo = repo,
        rev = rev,
        subdir = subdir,
        hash = hash,
        tree_hash = tree_hash,
    )
end

format(nothing) = ""
format(u::UUID) = string(u)
format(other::VersionNumber) = string(other)
format(x::PinnedPackage) = Dict(
    "uuid" => x.uuid,
    "version" => x.version,
    "repo" => x.repo,
    "rev" => x.rev,
    "subdir" => x.subdir,
    "hash" => x.hash,
    "tree_hash" => x.tree_hash,
)

function load_dependencies(
    context;
    path_project::String,
    path_lock::Union{String,Nothing} = nothing,
)
    if isnothing(path_lock)
        path_lock = "$path_project/Lock.toml"
    end
    existing_deps = Dict{String,PinnedPackage}()
    if isfile(path_lock)
        existing_deps = Dict{String,PinnedPackage}(
            name => PinnedPackage(
                uuid = UUID(kwargs["uuid"]),
                version = kwargs["version"] == "" ? nothing :
                          VersionNumber(kwargs["version"]),
                repo = kwargs["repo"] == "" ? nothing : kwargs["repo"],
                rev = kwargs["rev"] == "" ? nothing : kwargs["rev"],
                subdir = kwargs["subdir"] == "" ? nothing : kwargs["subdir"],
                hash = kwargs["hash"] == "" ? nothing : kwargs["hash"],
                tree_hash = get(kwargs, "tree_hash", "") == "" ? nothing :
                            kwargs["tree_hash"],
            ) for (name, kwargs) in TOML.parsefile(path_lock)["deps"]
        )
    end

    @assert length(context.registries) == 1
    dependencies = Pkg.dependencies(context.env)
    @info "Pinning $(length(dependencies)) dependencies"
    temp_dir = Filesystem.mktempdir()
    pinned_dependencies = Dict()
    for (uuid, info) in dependencies
        pinned = pin_package(
            context,
            uuid,
            info;
            temp_dir = temp_dir,
            existing = get(existing_deps, info.name, nothing),
        )
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

    if path_lock == "-"
        writer(stdout)
    else
        open(writer, path_lock, "w")
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
            path_lock = get(args, "output", nothing),
        )
    end
end

end
