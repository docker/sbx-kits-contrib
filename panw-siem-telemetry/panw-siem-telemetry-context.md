## SIEM telemetry

This sandbox forwards its observability data to an external SIEM HTTP event
collector via a Fluent Bit forwarder running in the background. Process,
network, file, and agent-activity logs written under `/var/log/sandbox/` and
`~/.sandbox/logs/` are tailed and shipped continuously.

To emit a custom event into the pipeline, append a JSON line to a `.log`
file under `~/.sandbox/logs/`. The collector token is proxy-managed - the
container never holds the real credential.
