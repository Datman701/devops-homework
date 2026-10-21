# Monitoring

The monitoring stack is intentionally lightweight so it fits beside TaskBoard on
a single-node minikube cluster. It uses plain Deployments and ConfigMaps rather
than the full kube-prometheus-stack.

## Components

| Object | Purpose |
| --- | --- |
| `namespace.yaml` | `monitoring` namespace |
| `prometheus-config.yaml` | scrape config: Prometheus, node-exporter, TaskBoard |
| `prometheus-alerts.yaml` | TaskBoard and node alert rules |
| `prometheus.yaml` | Prometheus 2.54 Deployment and Service |
| `grafana.yaml` | Grafana 11.2 Deployment and Service |
| `grafana-datasource.yaml` | provisioned Prometheus datasource |
| `grafana-dashboards-provider.yaml` | dashboard file provider |
| `grafana-dashboard.yaml` | TaskBoard overview dashboard |
| `node-exporter.yaml` | host metrics DaemonSet |

The TaskBoard scrape job is:

```yaml
- job_name: 'taskboard-backend'
  metrics_path: /metrics
  static_configs:
    - targets: ['taskboard-backend.taskboard.svc.cluster.local:8000']
```

## Deploy

```bash
kubectl apply -f monitoring/namespace.yaml
kubectl apply -n monitoring \
  -f monitoring/prometheus-config.yaml \
  -f monitoring/prometheus-alerts.yaml \
  -f monitoring/prometheus.yaml \
  -f monitoring/grafana-datasource.yaml \
  -f monitoring/grafana-dashboards-provider.yaml \
  -f monitoring/grafana-dashboard.yaml \
  -f monitoring/grafana.yaml \
  -f monitoring/node-exporter.yaml
```

## Access

```bash
kubectl -n monitoring port-forward svc/prometheus 19090:9090
kubectl -n monitoring port-forward svc/grafana 13002:3000
```

- Prometheus: <http://localhost:19090>
- Grafana: <http://localhost:13002> (`admin` / `admin` for this local demo)

## Verified

Prometheus reported all three targets `up`:

```text
node               up
prometheus         up
taskboard-backend  up
```

The Grafana dashboard `TaskBoard — Application Overview` includes:

- scrape target health
- requests since start
- p95 latency
- 5xx error ratio
- requests by endpoint
- latency percentiles
- responses by status
- requests by method

## Alerts

`TaskBoardTargetDown`, `TaskBoardHighErrorRate`, `TaskBoardHighLatency`, and
`TaskBoardHighRequestRate` are loaded from `prometheus-alerts.yaml`. The rules
are evaluated by the same Prometheus instance; no Alertmanager is configured in
this local demo.
