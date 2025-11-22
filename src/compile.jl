# Builds the current project's package
#
# This file cannot rely on any non-stdlib package since it needs to bootstrap
# these packages in Nix in the first place.

import Pkg
using Pkg.Types: Context
using Base: UUID

function create_build_paths(context::Context, uuids::Set{UUID})
    for uuid in uuids
        Pkg.Types.is_stdlib(uuid) && continue
        if Pkg.Types.is_project_uuid(context.env, uuid)
            #path = dirname(ctx.env.project_file)
            #name = ctx.env.pkg.name
            #version = ctx.env.pkg.version
        else
            entry = Pkg.Types.manifest_info(context.env.manifest, uuid)
            if entry === nothing
                @error "could not find entry with uuid $uuid in manifest $(context.env.manifest_file)"
            end
            name = entry.name
            path = Pkg.Operations.source_path(context.env.manifest_file, entry)
            if path === nothing
                @error "Failed to find path for package $name"
            end
            @info "Creating path: $path"
            Base.Filesystem.mkpath(path)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    context = Context()
    @info "Building $(context.env.pkg) ..."

    if !isfile(context.env.manifest_file)
        @error "A manifest file must exist!"
        exit(2)
    end

    Pkg.Operations.prune_manifest(context.env)

    for (uuid, entry) in context.env.manifest
        #@info "Slug: $(Base.version_slug(entry.uuid, entry.tree_hash))"
        #@info "Path: $(entry.path)"
        if Base.locate_package(Base.PkgId(uuid, entry.name)) === nothing
            @info "Cannot locate $(entry.name) [$uuid]"
        end
    end

    pkgs = Pkg.Operations.load_all_deps(context.env)

    @info "Checking $(length(context.env.manifest)) dependencies ..."

    @info "Precompiling $pkgs"

    pkgs = [pkg for pkg in pkgs if !Pkg.Types.is_stdlib(pkg.uuid, VERSION)]

    Pkg.API.precompile(context, [context.env.pkg]; already_instantiated = true)

    @info "Building ..."
    uuids = Set{UUID}(pkg.uuid for pkg in pkgs)
    create_build_paths(context, uuids)
    #Pkg.API.build(context, pkgs; verbose = true)
    #Pkg.Operations.build_versions(context, uuids; verbose = true)
end
