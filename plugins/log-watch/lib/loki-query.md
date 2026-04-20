# Loki Query Patterns

Shared LogQL and endpoint conventions for `log-watch`.

## Endpoint

The homelab Loki instance is exposed via K3s NodePort:

```
http://<k3s-node>:30100
```

Any reachable K3s node works. For most hosts inside the LAN, `192.168.0.147:30100` (PVE1) is fine. Confirm with `~/gitea-repos/homelab-setup/k8s/infrastructure/loki/nodeport.yaml` if the port changes.

The query endpoint is:

```
GET /loki/api/v1/query_range?query=<LogQL>&start=<ns>&end=<ns>&limit=<n>&direction=backward
```

## Auth

No auth on the NodePort — network-level access only. Do **not** expose this port outside the LAN.

## Severity-tagged LogQL

All handler skills filter by severity keyword after fetching. The baseline query selects everything from a target namespace and label-matches on common severity tokens:

```
{namespace="<ns>"} |~ "(?i)(error|exception|traceback|panic|fatal)"
```

For warnings:

```
{namespace="<ns>"} |~ "(?i)(warn|warning)" !~ "(?i)error"
```

For debug (opt-in only — high volume):

```
{namespace="<ns>"} |~ "(?i)debug"
```

## Namespaces currently shipped to Loki

Via Alloy DaemonSet (see `k8s/infrastructure/alloy/helmrelease.yaml`). The authoritative namespace→{repo, services} map lives in `lib/namespace-repo-map.md` — query selectors should derive from that list.

## Rate limits & windows

- Keep `limit` ≤ 1000 per query to stay under Loki's default max.
- Use `start`/`end` as nanosecond Unix timestamps. For a 15-minute window ending now:

```bash
END_NS=$(date +%s%N)
START_NS=$(( END_NS - 15*60*1000000000 ))
```

- For backward (newest-first) results, use `direction=backward`. This is what `watch-logs` uses so dedup sees the most recent events first.

## Response shape

```json
{
  "status": "success",
  "data": {
    "resultType": "streams",
    "result": [
      {
        "stream": { "namespace": "dragon-den", "pod": "...", "container": "..." },
        "values": [
          ["<timestamp_ns>", "<log line>"],
          ...
        ]
      }
    ]
  }
}
```

Parse streams in order, extract `(timestamp_ns, line, stream.pod, stream.namespace)` tuples for downstream handlers.
