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
julia --project=. monitor.jl --interval z iterations k --outdir /home/you/output
```
This will save a csv file, every z seconds, for k iterations, where 1 line represents the state of each node in the cluster, recording total/free CPU/RAM/GPU and node status (IDLE, ALLOC, ...). 

On specified conditions (IDLE->DOWN) will send messages to a linked Slackbot


## Dependencies
- Requires a link to a Slackbot
- Requires SLURM + command line tools (sinfo, scontrol) to be installed

