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
julia --project=. monitor.jl --interval 10 iterations 10 --outdir /home/you/output
```
