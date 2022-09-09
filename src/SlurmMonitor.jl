# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# Copyright 2020-2022, Ben Cardoen
module SlurmMonitor



using Logging
using ArgParse
using DataFrames
using Printf
using Plots
using GR
using Dates
using Statistics
using Slack
using CSV
using ProgressMeter


export monitor, plotstats, posttoslack, STATES, BADSTATE, GOODSTATE, summarizestate, sectime, pinghost, getnodes, decodenodes

STATES = ["ALLOC", "ALLOCATED", "CLOUD", "COMP", "COMPLETING", "DOWN", "DRAIN" , "DRAINED", "DRAINING", "FAIL", "FUTURE", "FUTR", "IDLE", "MAINT", "MIX", "MIXED", "NO_RESPOND","NPC", "PERFCTRS", "PLANNED", "POWER_DOWN", "POWERING_DOWN", "POWERED_DOWN", "POWERING_UP","REBOOT_ISSUED", "REBOOT_REQUESTED", "RESV", "RESERVED", "UNK", "UNKNOWN"]
BADSTATE = ["DOWN", "DOWN*", "DRAIN" , "DRAINED", "DRAINING", "FAIL", "MAINT", "NO_RESPOND", "POWER_DOWN", "POWERING_DOWN", "POWERED_DOWN", "POWERING_UP","REBOOT_ISSUED", "REBOOT_REQUESTED"]
GOODSTATE = ["ALLOC", "ALLOCATED", "IDLE", "MIXED"]


function plotstats(df)
    cdf=combine(groupby(df, [:INDEX, :TIME]), [:FREERAM => sum, :TOTALRAM => sum, :TOTALGPU => sum, :FREEGPU => sum, :TOTALCPU=>sum, :FREECPU=>sum, :AVGLATENCY=>mean])
    start=minimum(cdf.TIME)
    stop=maximum(cdf.TIME)
    F=unique(cdf.TOTALGPU_sum)[1]
    C=unique(cdf.TOTALCPU_sum)[1]
    bzp, idp, bap, total = quantifystates(df)
    R=unique(cdf.TOTALRAM_sum)[1]
    px = Plots.plot(cdf.INDEX, cdf.FREECPU_sum ./ cdf.TOTALCPU_sum .*100, ylim=[0,100], label="Free CPU (%) Total CPU=$(Int(C)) cores")
    Plots.plot!(cdf.INDEX, cdf.FREEGPU_sum ./ cdf.TOTALGPU_sum .*100, ylim=[0,100], label="Free GPU (%) Total GPU = $F GPUS")
    # Plots.plot!(cdf.INDEX, cdf.FREEGPU_sum ./ cdf.TOTALGPU_sum .*100, ylim=[0,100], label="Idle (%) Total Nodes = $total nodes")
    Plots.plot!(cdf.INDEX, idp .*100, ylim=[0,100], label="Idle (%) Total Nodes = $total nodes")
    Plots.plot!(cdf.INDEX, bap .*100, ylim=[0,100], label="BAD-DOWN (%)")
    Plots.plot!(cdf.INDEX, cdf.FREERAM_sum ./ cdf.TOTALRAM_sum *100, ylim=[0,120], label="Free RAM (%) Total RAM = $R GB")
    px=Plots.plot(px, dpi=90, size=(900, 800), ylabel="Available resources Solar (%)", xlabel="Time ($start --> $stop)", ylim=[0, 120])
    Plots.savefig("slurm.png")
    return px
end

function summarizestate(df, endpoint=nothing)
    _summarizestate(df, endpoint)
    _summarizestate(slice_hours(df, 24), endpoint)
end

function _summarizestate(df, endpoint)
    cdf=combine(groupby(df, [:INDEX, :TIME]), [:RUNNING => maximum, :QUEUE => maximum, :FREERAM => sum, :TOTALRAM => sum, :TOTALGPU => sum, :FREEGPU => sum, :TOTALCPU=>sum, :FREECPU=>sum, :AVGLATENCY=>mean])
    # cdf=combine(groupby(df, [:INDEX, :TIME]), [:QUEUE => maximum, :FREERAM => sum, :TOTALRAM => sum, :TOTALGPU => sum, :FREEGPU => sum, :TOTALCPU=>sum, :FREECPU=>sum])
    start=minimum(cdf.TIME)
    stop=maximum(cdf.TIME)
    F=unique(cdf.TOTALGPU_sum)[1]
    C=unique(cdf.TOTALCPU_sum)[1]
    bzp, idp, bap, total = quantifystates(df)
    R=unique(cdf.TOTALRAM_sum)[1]
    RQ=cdf.RUNNING_maximum[end]
    QQ=cdf.QUEUE_maximum[end] - cdf.RUNNING_maximum[end]
    # QQ=cdf.QUEUE_maximum[end] .- cdf.RUNNING_maximum[end]
    CQ=cdf.QUEUE_maximum .- cdf.RUNNING_maximum
    msgs=[]
    push!(msgs,"Last $(sectime(df)) hours, utilization of cluster:")
    # push!(msgs,"Nodes = $(total[end]) μ busy $(@sprintf("%.2f", bzp[end] *100))%")
    push!(msgs,"Nodes = $(total[end]) μ busy $(@sprintf("%.2f", bzp[end] *100))% -- CPU $(Int.(C)) μ busy $(@sprintf("%.2f", 100-mean(cdf.FREECPU_sum ./ cdf.TOTALCPU_sum .*100)))% -- GPUs $(Int.(F)) μ busy $(@sprintf("%.2f", 100-mean(cdf.FREEGPU_sum ./ cdf.TOTALGPU_sum .*100)))%")
    # push!(msgs,"GPUs $(Int.(F)) μ Utilization $(@sprintf("%.2f", 100-mean(cdf.FREEGPU_sum ./ cdf.TOTALGPU_sum .*100)))%")
    # push!(msgs,"Running = $(Int.(RQ)) Queued = $(Int.(QQ))")
    push!(msgs,"Jobs: Running = $(Int.(RQ)) Queued = $(Int.(QQ)) -- μ, max queue length $(@sprintf("%.2f", mean(CQ))), $(@sprintf("%.2f", maximum(CQ)))")
    # push!(msgs,"max queue length $(@sprintf("%.2f", maximum(CQ)))")
    posttoslack(join(msgs, "\n"), endpoint)
end


function sectime(df)
    s = (maximum(df.INDEX) - minimum(df.INDEX))*unique(df.INTERVAL)[1]
    round(s / 3600)
end

function quantifystates(df)
    indices=sort(unique(df.INDEX))
    bzp = []
    idp = []
    bap = []
    total = 0
    for i in indices
        states = df[df.INDEX .== i,:].STATE
        idle, busy, bad = enumeratestates(states)
        # @info idle, busy, bad
        total = idle+busy+bad
        push!(bzp, busy/total)
        push!(idp, idle/total)
        push!(bap, bad/total)
    end
    return bzp, idp, bap, total
end

function enumeratestates(states)
    idle, busy, bad = 0, 0, 0
    for state in states
        if state ∈ ["IDLE"]
            idle = idle + 1
        end
        if state ∈ ["ALLOC", "ALLOCATED", "IDLE", "MIXED"]
            busy = busy + 1
        end
        if state ∈ BADSTATE
            bad = bad + 1
        end
    end
    return idle, busy, bad
end

function getnodes()
    nds=[_n[1] for _n in split.(readlines(`sinfo -hN`), ' ')]
    return unique(nds)
    # r=split(readlines(`sinfo -o"%N"`)[2], ',')
    # nodes = decodenodes(r)
    # return nodes
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
    if state ∈ BADSTATE
        @warn "$nodename is not in valid state $state"
        return state, 0, 0, 0, 0, 0, 0, "UNKNOWN"
    end
    ncpu=tryparse(Int64, getfield(res, "CPUTot="))
    freecpu=ncpu-tryparse(Int64, getfield(res, "CPUAlloc="))
    # @info "Total $ncpu Allocated $freecpu"
    totalmemory=tryparse(Float64, getfield(res, "RealMemory="))
    freememory=tryparse(Float64, getfield(res, "FreeMem="))
    # @info "Total memory $totalmemory free $freememory"
    gpualloc=alloctres(res)
    totalgpu=tryparse(Int, split(filter(y->occursin("Gres=", y), res)[1],':')[end])
    k2 = "unknown"
    try
        k=split(filter(y->occursin("OS=Linux", y), res)[1], ' ')
        k2=filter(z->occursin("-generic", z),k)[1]
    catch e
        @error "Exception $e occurred during parsing of Kernel version for node $nodename $res"
    end
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
    @warn "Remove key"
    output = readlines(`ssh -i $key $(node) -p $port $command`)
    return output
end

function diskusage(node)
    command="df -H"
    outp = remotecall(node, command)
    decoded = decodeusage(outp)
    return decoded
end


function posttoslack(message, endpoint=nothing)
    if isnothing(endpoint)
        @warn "Sent $message to empty endpoint ... ignoring"
    else
        try
            response = sendtoslack(message, endpoint)
            @info "Sent $message to $endpoint with response $response"
        catch e
            @error "Failed sending $message to $endpoint with exception $e"
        end
    end
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


function pinghost(host, count=100, interval=1)
    # Todo protect from crashing
    sq = [""]
    try
        sq = readlines(`ping -A -i $interval $host -c $count`)[end-1:end]
    catch e
        @error "Ping to $host failed with exception $e"
        return Inf64, Inf64, Inf64, Inf64, 100
    end
    lostline = split(sq[1], ',')[3]
    mi, av, ma, md = tryparse.(Float64, split(split(sq[2])[4], '/'))
    li = findfirst("%", lostline)
    lostpercent = tryparse(Float64, lostline[1:li[1]-1])
    @debug "Ping statistics for host $host with $count packets:"
    @debug "Min-max [$mi, $ma] ms, μ = $av ± $md with $lostpercent % lost packets"
    return mi, av, ma, md, lostpercent
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
        #@info "Current SLURM : $(length(states)) jobs with $(run) running"
    end
    return states, run
end


function getkernel(node)
    return remotecall(node, "uname -r")
end

function monitor(; interval=60, iterations=60*24, outpath=".", endpoint=nothing, minlatency=50)
    r=iterations
    index=1
    recorded = DataFrame(NODE=String[], TIME=String[], INTERVAL=Int64[],
                INDEX=Int64[], STATE=String[], TOTALGPU=Int64[], FREEGPU=Int64[],
                TOTALRAM=Float64[], FREERAM=Float64[], TOTALCPU=Float64[],
                FREECPU=Float64[], QUEUE=Int64[], RUNNING=Int64[], KERNEL=String[], MINLATENCY=Float64[], MAXLATENCY=Float64[], AVGLATENCY=Float64[], STDLATENCY=Float64[], LOSTPACKETS=Float64[])
    @info "Starting loop, polling every $interval seconds"
    time = Dates.format(now(Dates.UTC), "dd-mm-yyyy HH:MM")
    @info "Start at $time"
    while true
        sleep(interval)
        states, running =queuelength()
        time = Dates.format(now(Dates.UTC), "dd-mm-yyyy HH:MM")
        nodes = getnodes()
        @showprogress for node in nodes
            state, ncpu, freecpu, totalmemory, freememory, totalgpu, freegpu, kernel=getnodestatus(node)
            mi, avg, ma, st, lost = pinghost(node)
            push!(recorded, [node, time, interval, index, state, totalgpu, freegpu,
            totalmemory, freememory, ncpu, freecpu,
            length(states), running, kernel, mi, ma, avg, st, lost])
            if avg > minlatency
                @error "Node $node latency has exceed threshold $minlatency"
            end
        end
        triggernode(recorded, endpoint; minlatency)
        if r != -1
            r = r -1
            if r < 1
                @info "halting"
                summarizestate(recorded, endpoint)
                break
            end
        end
        index = index + 1
        CSV.write(joinpath(outpath, "observed_state.csv"), recorded)
    end
    CSV.write(joinpath(outpath, "observed_state.csv"), recorded)
end

function slice_hours(df, h)
    secs = unique(df.INTERVAL)[1]
    mai, mii = maximum(df.INDEX), minimum(df.INDEX)
    tm=h * 60 * 60
    ind=Int.(round(tm/secs))
    last = max(1, mai - ind)
    @info last
    copy(df[df.INDEX .> last, :])
end

function triggernode(recorded, endpoint=nothing; minlatency)
    lastindex=maximum(recorded[!, :INDEX])
    if lastindex == 1
        @info "Only 1 recording, no sense in checking"
        return
    end
    laststate = recorded[recorded.INDEX .== lastindex-1, :]
    curstate = recorded[recorded.INDEX .== lastindex, :]
    nodes = laststate.NODE
    trig = false
    for node in nodes
        lastnodestate = laststate[laststate.NODE .== node, :].STATE[1]
        curnodestate = curstate[curstate.NODE .== node, :].STATE[1]
        if curnodestate ∈ BADSTATE
            @warn "$node has bad state $curnodestate"
            if lastnodestate ∈ GOODSTATE
                @error "Node switched from $lastnodestate to $curnodestate"
                # trigger(node, lastnodestate, curnodestate, curstate)
                posttoslack("-!- Warning-!- Node $node switched from $lastnodestate to $curnodestate at $(curstate[curstate.NODE .== node, :].TIME[1])", endpoint)
                trig = true
            end
        end
        if curnodestate ∈ GOODSTATE
            # @warn "$node has good state $curnodestate"
            if lastnodestate ∈ BADSTATE
                @info "Node switched from $lastnodestate to $curnodestate"
                # trigger(node, lastnodestate, curnodestate, curstate)
                posttoslack("✓ Resolved ✓ Node $node switched from $lastnodestate to $curnodestate at $(curstate[curstate.NODE .== node, :].TIME[1])", endpoint)
                trig = true
            end
        end
        curnodelatency = curstate[curstate.NODE .== node, :].AVGLATENCY[1]
        lastnodelatency = laststate[laststate.NODE .== node, :].AVGLATENCY[1]

        if curnodelatency > minlatency
            if lastnodelatency < minlatency
                @warn "Node $node has latency > minlatency"
                # trigger(node, lastnodestate, curnodestate, curstate)
                posttoslack("-!- Warning-!- Node $node has latency > $minlatency , possibly non-responsive at $(curstate[curstate.NODE .== node, :].TIME[1])", endpoint)
                trig = true
            else
                @warn "Node still unreachable, but we have warned earlier."
            end
        end
    end
    if trig
        summarizestate(recorded, endpoint)
        # summarizestate(slice_hours(recorded, 24))
    end
    return
end


end
