using ..Manifest2Nix: Manifest
import ArgParse
import Pkg

function main()
    settings = ArgParse.ArgParseSettings(
        description = "Manifest2Nix",
        commands_are_required = true,
        version = string(VERSION),
        add_version = true,
        add_help = true,
    )
    ArgParse.@add_arg_table! settings begin
        "lock"
        help = "Generate lock file"
        action = :command
    end
    ArgParse.@add_arg_table! settings["lock"] begin
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
    args = ArgParse.parse_args(ARGS, settings)

    command = args["%COMMAND%"]
    if command == "lock"
        Manifest.main(args["lock"])
    else
        error("Unknown command $command")

    end
end
