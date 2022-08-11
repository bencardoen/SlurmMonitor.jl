# SlurmMonitor

SlurmMonitor monitors SLURM (an HPC scheduler) based clusters for status, records the data over time, and if configured can act on predefined conditions.

## Installation
```bash
git clone <thisrepo>
cd SlurmMonitor.jl
julia
```
Then
```julia
add .
```


## Usage
Every 10 seconds, 10 times, record cluster state and save csv in /home/you/output
```bash
julia --project=. monitor.jl --interval z iterations k --outdir /home/you/output --endpoint services/....
```
This will save a csv file, every z seconds, for k iterations, where 1 line represents the state of each node in the cluster, recording total/free CPU/RAM/GPU and node status (IDLE, ALLOC, ...).

On specified conditions (IDLE->DOWN) will send messages to a linked Slackbot, configured with endpoint.


## Dependencies
- Requires a link to a Slackbot
- Requires SLURM + command line tools (sinfo, scontrol) to be installed



## Warning
If you run this on a cluster, make sure you're authorized to do so. Calling `scontrol` and `sinfo` are RPC calls that cause a non-trivial load on the scheduler, if the cluster has 1000s of nodes, and you set the interval to 1s, that means 2000 RPC calls/1.
Note that it takes several seconds, if not more, for a node to change state anyway.
Do not do this unless you're a cluster admin.
Sane intervals are ~ 120 or more seconds.
