# Builds the main target of the current project.

import Pkg

if abspath(PROGRAM_FILE) == @__FILE__
    Pkg.Registry.rm("General")
    context = Pkg.Types.Context()
    println("$(context.env.pkg)")
    Pkg.API.precompile(context, [context.env.pkg]; already_instantiated = true)
    Pkg.API.build(context, [context.env.pkg]; verbose = true)
end
