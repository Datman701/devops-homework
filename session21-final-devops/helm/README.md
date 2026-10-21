# Helm Chart — `taskboard`

The chart deploys PostgreSQL, the FastAPI backend, the React frontend, an
optional Ingress, and an optional HorizontalPodAutoscaler.

## Values

| Key | Default | Notes |
| --- | --- | --- |
| `backend.image` / `backend.tag` | `taskboard-backend:local` | CI overrides with GHCR image + SHA |
| `frontend.image` / `frontend.tag` | `taskboard-frontend:local` | CI overrides with GHCR image + SHA |
| `replicaCount` | `2` | frontend replicas |
| `postgres.host` | `taskboard-postgres` | matches the release name `taskboard` |
| `postgres.storageSize` | `5Gi` | PVC request |
| `ingress.enabled` | `false` | enable for the local demo |
| `ingress.host` | `taskboard.local` | |
| `hpa.enabled` | `true` | backend HPA |
| `hpa.minReplicas` / `maxReplicas` | `2` / `6` | |
| `hpa.targetCPUUtilizationPercentage` | `60` | |
| `imagePullSecrets` | `[]` | set for private GHCR packages |

`values-dev.yaml` enables the Ingress with one frontend replica and disables the
HPA. `values-prod.yaml` is the production-shaped example with GHCR images and a
real hostname.

## Render and lint

```bash
helm lint helm/taskboard
helm template taskboard helm/taskboard \
  --namespace taskboard \
  --set ingress.enabled=true \
  --set ingress.host=taskboard.local
```

## Install

```bash
helm upgrade --install taskboard helm/taskboard \
  --namespace taskboard --create-namespace \
  --set ingress.enabled=true \
  --set ingress.host=taskboard.local \
  --set hpa.enabled=true
```

For a CI-built image:

```bash
helm upgrade --install taskboard helm/taskboard \
  --namespace taskboard --create-namespace \
  --set backend.image=ghcr.io/datman701/taskboard-backend \
  --set backend.tag=<commit-sha> \
  --set frontend.image=ghcr.io/datman701/taskboard-frontend \
  --set frontend.tag=<commit-sha>
```

## Naming

All resources use `{{ include "taskboard.fullname" . }}` and the release is named
`taskboard`, so Services are `taskboard-backend`, `taskboard-frontend`, and
`taskboard-postgres`. The Ingress and HPA reference those exact names.

## Probes

The backend has a startup probe (`/health`), readiness probe (`/ready`), and
liveness probe (`/health`). The frontend probes `/` on port 80. PostgreSQL uses
`pg_isready`.
