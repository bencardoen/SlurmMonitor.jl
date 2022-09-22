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
You install the monitor on a **login** node, and this assumes HPC admins are ok with you doing this.
```bash
git clone <thisrepo>
cd SlurmMonitor.jl
```
Then start julia
```bash
julia
```
```julia
julia> using Pkg; Pkg.add(".")
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
The monitor polls at intervals **i**, repeating **r** times, with minimum acceptable latency **l** and saving to output dir **o**.
Triggers (node going down, latency spikes), trigger optional messages to Slack **e**.
It needs and endpoint file (1 line), with a endpoint (see earlier).
You'd use this within a tmux/screen session to keep it in the background.
### Example
Every minute, for 1e4 minutes, run the monitor, and call Solar Slack if issues arise.
```bash
julia --project=. src/monitor.jl -i 60 -r 10000 -o . -e endpoint_solar.txt -l 40
```
This will save a csv file, every z seconds, for k iterations, where 1 line represents the state of each node in the cluster, recording total/free CPU/RAM/GPU and node status (IDLE, ALLOC, ...).

On specified conditions (IDLE->DOWN) will send messages to a linked Slackbot, configured with the right endpoint.

If a node is not responsive (by network), a similar trigger is fired. Define the mininum average latency you consider as not-reachable in CLI.

### Output
Saved to `observed_state.csv`

## Dependencies
- Julia [https://julialang.org/downloads/](https://julialang.org/downloads/)
- Requires a link to a Slackbot
- Requires SLURM + command line tools (sinfo, scontrol) to be installed



## Warning
If you run this on a cluster, **make sure you're authorized to do so**. Calling `scontrol` and `sinfo` are RPC calls that cause a non-trivial load on the scheduler, if the cluster has 1000s of nodes, and you set the interval to 1s, that means 2000 RPC calls/1.
Note that it takes several seconds, if not more, for a node to change state anyway.
Do not do this unless you're a cluster admin.
**Sane intervals are ~ 60-120 or more seconds.**

## Extra functionality
- Triggers can be anything, currently node state and latency are used
- Diskusage, nvidia drivers, etc are all implemented, not active (can trigger ssh lockout)
- **Contact me if you need those active**
