using ..Manifest2Nix: Manifest
import ArgParse
import Pkg

function main()
    settings = ArgParse.ArgParseSettings()
    @ArgParse.add_arg_table! settings begin
        "-p" "--project"
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
    config = ArgParse.parse_args(settings)

    Pkg.Operations.with_temp_env(config["project"]) do
        Manifest.load_dependencies(path_output=get(config, "output", nothing))
    end
end
