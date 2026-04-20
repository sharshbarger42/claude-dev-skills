# Namespace → Repo Map

Authoritative mapping from K3s namespace (used in Loki queries) to the owning Gitea repo and the service(s) running in that namespace. Shared across `watch-logs` and the severity handler skills so the mapping lives in one place.

| Namespace | Repo path | Services |
|-----------|-----------|----------|
| `dragon-den` | `~/gitea-repos/dragon-den` | dragon-den FastAPI app |
| `food-automation` | `~/gitea-repos/food-automation` | Grocy voice/photo assistant |
| `multi-agent-coordinator` | `~/gitea-repos/multi-agent-coordinator` | MAC orchestrator |
| `camping-planner-sandbox` | `~/gitea-repos/camping-planner-sandbox` | Go app (dev/test) |

For namespaces not listed here, skip code-lookup steps and proceed with log context only.

Regex selector that matches all shipped namespaces:

```
{namespace=~"dragon-den|food-automation|multi-agent-coordinator|camping-planner-sandbox"}
```
