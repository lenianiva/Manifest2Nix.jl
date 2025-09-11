using ..Manifest2Nix: Manifest
import ArgParse
import Pkg

function main()
    settings = ArgParse.ArgParseSettings()
    @ArgParse.add_arg_table! settings begin
        "-p", "--project"
            help = "Root to project"
            required = false
            arg_type = String
            default = pwd()
        "-o", "--output"
            help = "Output manifest file"
            required = false
            arg_type = String
            default = nothing
    end
    config = ArgParse.parse_args(ARGS, settings)

    path_project = config["project"]
    Pkg.Operations.with_temp_env(path_project) do
        @info "Creating context for project $path_project"
        context = Pkg.Types.Context()

        @info "Processing dependencies for project $(context.env.project.name)"
        Manifest.load_dependencies(context, path_output=get(config, "output", nothing))
    end
end
