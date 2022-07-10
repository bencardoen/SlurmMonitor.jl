module SlurmMonitor

# Write your package code here.


using Logging
using ArgParse
using DataFrames
using Dates
using CSV
using ProgressMeter


export monitor

STATES = ["ALLOC", "ALLOCATED", "CLOUD", "COMP", "COMPLETING", "DOWN", "DRAIN" , "DRAINED", "DRAINING", "FAIL", "FUTURE", "FUTR", "IDLE", "MAINT", "MIX", "MIXED", "NO_RESPOND","NPC", "PERFCTRS", "PLANNED", "POWER_DOWN", "POWERING_DOWN", "POWERED_DOWN", "POWERING_UP","REBOOT_ISSUED", "REBOOT_REQUESTED", "RESV", "RESERVED", "UNK", "UNKNOWN"]
BADSTATE = ["DOWN", "DRAIN" , "DRAINED", "DRAINING", "FAIL", "MAINT", "NO_RESPOND", "POWER_DOWN", "POWERING_DOWN", "POWERED_DOWN", "POWERING_UP","REBOOT_ISSUED", "REBOOT_REQUESTED"]
GOODSTATE = ["ALLOC", "ALLOCATED", "IDLE", "MIXED"]

function getnodes()
    r=split(readlines(`sinfo -o"%N"`)[2], ',')
    nodes = decodenodes(r)
    return nodes
end

function getcpu(node)
    r = remotecall(node, "lscpu")
    rs=filter(x->startswith(x, "CPU(s):"), r)[1]
    cores=tryparse(Float64, split(rs)[end])
    l = remotecall(node, "uptime")
    ftload = tryparse(Float64, split(l[1])[end])
    @info "$(cores) for $node 15min avg usage = $((ftload/cores)*100) %"
    return cores, (ftload / cores)*100
end

function getfield(scontrolfield, field="State=")
    res=scontrolfield
    str= filter(x -> occursin(field,x), res)[1]
    b=findfirst(field, str)[end]
    e=findfirst(' ',str[b:end])
    state=str[b+1:b+e-2]
end

function getnodestatus(nodename)
    res=readlines(`scontrol show node $(nodename)`)
    state=getfield(res)
    ncpu=tryparse(Int64, getfield(res, "CPUTot="))
    freecpu=ncpu-tryparse(Int64, getfield(res, "CPUAlloc="))
    # @info "Total $ncpu Allocated $freecpu"
    totalmemory=tryparse(Float64, getfield(res, "RealMemory="))
    freememory=tryparse(Float64, getfield(res, "FreeMem="))
    # @info "Total memory $totalmemory free $freememory"
    gpualloc=alloctres(res)
    totalgpu=tryparse(Int, split(filter(y->occursin("Gres=", y), res)[1],':')[end])
    k=split(filter(y->occursin("OS=Linux", y), res)[1], ' ')
    k2=filter(z->occursin("-generic", z),k)[1]
    # @info "GPU allocated $gpualloc total $totalgpu"
    return state, ncpu, freecpu, totalmemory, freememory, totalgpu, totalgpu-gpualloc, k2
end

function alloctres(res)
    str= filter(x -> occursin("AllocTRES=",x), res)[1]
    start=findfirst("AllocTRES=", str)[end]
    sp=split(str, ',')
    gs = filter(x -> occursin("gres/gpu=", x),sp)
    if length(gs) == 0
        return 0
    else
        e=findfirst("gpu=", gs[1])[end]
        G=gs[1][e+1:end]
        return tryparse(Int64, G)
    end
end

function decodenodes(nodelist)
    nodes = []
    for t in nodelist
        b, e, = findfirst('[', t), findfirst(']', t)
        beg, en = split(t[b+1:e-1], '-')
        prefix = t[1:b-1]
        st = tryparse(Int, beg)
        ts = tryparse(Int, en)
        for num in st:ts
            #@info num
            if beg[1] == '0'
                push!(nodes, "$(prefix)0$num")
            else
                push!(nodes, "$(prefix)$num")
            end
        end
    end
    nodes
end

function sizetonumeric(sizestr::AbstractString)
    L = sizestr[end]
    # @info L
    Q = tryparse(Float64, sizestr[1:end-1])
    tbl = Dict([('G' => 0.001), ('T' => 1), ('M' => 0.000001)])
    r = Q * tbl[L]
    @debug "Parsed $sizestr to $r TB"
    return r
end

function decodeusage(usage)
    lc = filter(x -> occursin("localscratch", x), usage)[1]
    total, free, used=sizetonumeric.(split(lc)[2:4])
    @info "Total $total TB with $((used/total)*100) % used"
    return total, (used/total)*100
end

function remotecall(node, command, key="/home/bcardoen/.ssh/id_rsa", port=24)
    output = readlines(`ssh -i $key $(node) -p $port $command`)
    return output
end

function diskusage(node)
    command="df -H"
    outp = remotecall(node, command)
    decoded = decodeusage(outp)
    return decoded
end

function decode_nvidiasmi(nvidiasmi, nvidiasmil)
    devicecount = length(nvidiasmil)
    FT = filter(x -> occursin("%", x), nvidiasmi)
    utils = zeros(devicecount, 3)
    for (i, ft) in enumerate(FT)
        idx = findlast("%", ft)[1]
        idy = findlast(" ", ft[1:idx])[1]
        util=ft[idy+1:idx-1]
        futil = tryparse(Float64, util)
        fts=filter(x->occursin("MiB", x), split(ft))
        mu = fts[1][1:findfirst('M', fts[1])-1]
        tu = fts[2][1:findfirst('M', fts[2])-1]
        fmu = tryparse(Float64, mu)
        tfu = tryparse(Float64, tu)
        utils[i,:] .= futil, fmu, tfu
    end
    return utils
end


function nvidiaheader(nvidiasmi)
    header=split(filter(x -> occursin("NVIDIA-SMI", x), nvidiasmi)[1])
    d, c = "", ""
    for (i,h) in enumerate(header)
        if occursin("Version", h)
            if occursin("Driver", header[i-1])
                d = header[i+1]
            elseif occursin("CUDA", header[i-1])
                c = header[i+1]
            else
                @error "Unexpected NVIDIA-SMI header $header"
            end
            i = i+2
        end
    end
    @info "NVIDIA driver $d Cuda $c"
    return d, c
end

function decoderam(entry)
    if occursin("G", entry)
        return tryparse(Float64, entry[1:findfirst("G", entry)[1]-1])*0.001
    end
    if occursin("T", entry)
        return tryparse(Float64, entry[1:findfirst("T", entry)[1]-1])
    end
    if occursin("K", entry)
        return tryparse(Float64, entry[1:findfirst("K", entry)[1]-1])*.000001
    end
    if occursin("B", entry)
        return tryparse(Float64, entry[1:findfirst("B", entry)[1]-1])*.000000001
    end
    @error "Invalid entry $entry for RAM"
    return 0.0
end


function ramusage(node)
    ramusage = remotecall(node, "free -h")
    _ram = split(ramusage[2])
    _swap = split(ramusage[3])
    totalram, availram = decoderam(_ram[2]), decoderam(_ram[end])
    totalswap, availswap = decoderam(_swap[2]), decoderam(_swap[end])
    return totalram, availram, totalswap, availswap
end

function gpuusage(node)
    @info "Checking GPU for $node"
    NO = remotecall(node, "nvidia-smi -L")
    # @info NO
    NA = remotecall(node, "nvidia-smi")
    # @info NA
    r=decode_nvidiasmi(NA, NO)
    @info "Node has a total of $(size(r, 1)) GPUs"
    n = size(r, 1)
    for i in 1:n
        @info "GPU utilization $(r[i,1]) % with VRAM $(r[i, 2]) / $(r[i, 3]) GB"
    end
    driver, cuda = nvidiaheader(NA)
    return r, driver, cuda
end

function quantifygpu(r)
    busy = size(r[(r[:,1] .> 10) .& ((r[:,2] ./ r[:,3]) .> 0.1),:],1)
    return size(r, 1), busy
end

function queuelength()
    sq = readlines(`squeue --long`)
    if length(sq) > 1
        jobs = sq[3:end]
        states = [split(job)[5] for job in jobs]
        run=0
        for s in states
            if s == "RUNNING"
                run = run+1
            end
        end
        @info "Current SLURM : $(length(states)) jobs with $(run) running"
    end
    return states, run
end


function getkernel(node)
    return remotecall(node, "uname -r")
end

function monitor(; interval=60, iterations=60*24, outpath="/dev/shm")
    # interval=60
    r=iterations
    index=1
    recorded = DataFrame(NODE=String[], TIME=String[], INTERVAL=Int64[],
                INDEX=Int64[], STATE=String[], TOTALGPU=Int64[], FREEGPU=Int64[],
                TOTALRAM=Float64[], FREERAM=Float64[], TOTALCPU=Float64[],
                FREECPU=Float64[], QUEUE=Int64[], RUNNING=Int64[], KERNEL=String[])
    @info "Starting loop, polling every $interval seconds"
    time = Dates.format(now(Dates.UTC), "dd:mm:yyyy HH:MM")
    @info "Start at $time"
    while true
        # @info "Sleeping for $interval seconds"
        sleep(interval)
        states, running =queuelength()
        time = Dates.format(now(Dates.UTC), "dd:mm:yyyy HH:MM")
        nodes = getnodes()
        @showprogress for node in nodes
            state, ncpu, freecpu, totalmemory, freememory, totalgpu, freegpu, kernel=getnodestatus(node)
            push!(recorded, [node, time, interval, index, state, totalgpu, freegpu,
            totalmemory, freememory, ncpu, freecpu,
            length(states), running, kernel])
        end
        # @info recorded
        ## Todo
        ## For node in nodes
        ## Check current state with last state and if triggered -> notify
        triggernode(recorded, index, interval, x->x, nodes)
        if r != -1
            r = r -1
            if r < 1
                @info "halting"
                break
            end
        end
        index = index + 1
    end
    CSV.write("observed_state.csv", recorded)
end

function triggernode(recorded, index, interval, trigger, nodes)
    @info "Testing health of cluster nodes"
    if index == 1
        @debug "First state, skipping trigger"
        return
    end
    laststate = recorded[recorded.INDEX .== index-1, :]
    curstate = recorded[recorded.INDEX .== index, :]
    for node in nodes
        lastnodestate = laststate[laststate.NODE .== node, :].STATE[1]
        curnodestate = curstate[curstate.NODE .== node, :].STATE[1]
        if curnodestate ∈ BADSTATE
            @warn "$node has bad state $curnodestate"
            if lastnodestate ∈ GOODSTATE
                @error "Node switched from $lastnodestate to $curnodestate"
                # trigger(node, lastnodestate, curnodestate, curstate)
            end
        end
    end
    return
end


end
