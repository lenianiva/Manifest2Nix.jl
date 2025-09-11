# Builds the current project's package
#
# This file cannot rely on any non-stdlib package since it needs to bootstrap
# these packages in Nix in the first place.

import Pkg

if abspath(PROGRAM_FILE) == @__FILE__
    Pkg.Registry.rm("General")
    context = Pkg.Types.Context()
    println("$(context.env.pkg)")
    Pkg.API.precompile(context, [context.env.pkg]; already_instantiated = true)
    Pkg.API.build(context, [context.env.pkg]; verbose = true)
end
