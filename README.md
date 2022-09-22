# SlurmMonitor

SlurmMonitor monitors SLURM (an HPC scheduler) based clusters for status, records the data over time, and if configured can act on predefined conditions.

## Linking to Slack
** You need admin rights to do this, and do not create public endpoints without realizing what they (can) do**

- Login to Slack
- Settings and Admin
- "Manage Apps"
- "Build"
- Create a new App
- Activate new webhook
  - generates endpoint of form "https://hooks.slack.com/services/XXX/YYY/zzz"
  - Save in a file 'endpoint.txt'
  - Pass location of file to monitor.jl (see below)

### Test if link works
```bash
curl -X POST -H 'Content-type: application/json' --data '{"text":"Hello, World!"}' $URL
```

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
or
```bash
julia
```
then
```julia
julia>using Pkg; Pkg.activate() # Activate env in current dir, optional
julia>using Pkg; Pkg.add(url=<thisrepo>)
```



## Usage
Every 10 seconds, 10 times, record cluster state and save csv in /home/you/output
```bash
julia --project=. monitor.jl --interval z iterations k --outdir /home/you/output --endpoint services/.... --min-latency 40
```
This will save a csv file, every z seconds, for k iterations, where 1 line represents the state of each node in the cluster, recording total/free CPU/RAM/GPU and node status (IDLE, ALLOC, ...).

On specified conditions (IDLE->DOWN) will send messages to a linked Slackbot, configured with the right endpoint.

If a node is not responsive (by network), a similar trigger is fired. Define the mininum average latency you consider as not-reachable in CLI.


## Dependencies
- Requires a link to a Slackbot
- Requires SLURM + command line tools (sinfo, scontrol) to be installed



## Warning
If you run this on a cluster, make sure you're authorized to do so. Calling `scontrol` and `sinfo` are RPC calls that cause a non-trivial load on the scheduler, if the cluster has 1000s of nodes, and you set the interval to 1s, that means 2000 RPC calls/1.
Note that it takes several seconds, if not more, for a node to change state anyway.
Do not do this unless you're a cluster admin.
Sane intervals are ~ 120 or more seconds.
