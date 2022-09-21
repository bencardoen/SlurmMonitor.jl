export LOCALPKG=/opt/SlurmMonitor.jl
export JLMJV=1.7
export JLV=$JLMJV.1
export PATH=/opt/julia/julia-$JLV/bin:$PATH
export JULIA_DEPOT_PATH=/opt/juliadepot
julia --project=/opt/SlurmMonitor.jl /opt/SlurmMonitor.jl/src/monitor.jl "$@"
#julia --project=/opt/SlurmMonitor.jl --sysimage /opt/SlurmMonitor.jl/sys_img.so "$@"
