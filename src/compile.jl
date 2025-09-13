# Builds the current project's package
#
# This file cannot rely on any non-stdlib package since it needs to bootstrap
# these packages in Nix in the first place.

import Pkg
using Base: UUID

if abspath(PROGRAM_FILE) == @__FILE__
    Pkg.Registry.rm("General")
    context = Pkg.Types.Context()
    @info "Building $(context.env.pkg) ..."

    if !isfile(context.env.manifest_file)
        @error "A manifest file must exist!"
        exit(2)
    end

    Pkg.Operations.prune_manifest(context.env)

    for (uuid, entry) in context.env.manifest
        @info "Trying to find dependency $(entry.name) [$uuid] ..."
        #@info "Slug: $(Base.version_slug(entry.uuid, entry.tree_hash))"
        @info "Path: $(entry.path)"
        if Base.locate_package(Base.PkgId(uuid, entry.name)) === nothing
            @error "Package $(entry.name) is not installed"
            exit(1)
        end
    end

    pkgs = Pkg.Operations.load_all_deps(context.env)

    @info "Checking $(length(context.env.manifest)) dependencies ..."

    @info "Precompiling $pkgs"

    pkgs = [pkg for pkg in pkgs if !Pkg.Types.is_stdlib(pkg.uuid, VERSION)]

    Pkg.API.precompile(context; already_instantiated = true)

    @info "Building ..."
    #Pkg.API.build(context, pkgs; verbose = true)
    uuids = Set{UUID}(pkg.uuid for pkg in pkgs)
    Pkg.Operations.build_versions(context, uuids; verbose = true)
end
