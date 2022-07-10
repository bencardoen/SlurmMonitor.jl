using ArgParse
using Logging
using Dates
using LoggingExtras
using SlurmMonitor


function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--interval", "-i"
            help = "Interval in seconds to poll. Minimum 10, default 60s."
            arg_type = Int
            default = 60
        "--iterations", "-r"
            help = "Number of iterations to keep running, set to -1 for infinite"
	    arg_type = Int
	    default = 60
    end
    return parse_args(s)
end



function run()
    p = parse_commandline()
    date_format = "yyyy-mm-dd HH:MM:SS"
    timestamp_logger(logger) = TransformerLogger(logger) do log
      merge(log, (; message = "$(Dates.format(now(), date_format)) $(basename(log.file)):$(log.line): $(log.message)"))
    end
    ConsoleLogger(stdout, Logging.Info) |> timestamp_logger |> global_logger
    parsed_args = parse_commandline()
    @info "Parsed arguments:"
    for (arg,val) in parsed_args
        @info "  $arg  =>  $val"
    end
    monitor(; interval=parsed_args["interval"], iterations=parsed_args["iterations"], outpath="/dev/shm")
end


run()
