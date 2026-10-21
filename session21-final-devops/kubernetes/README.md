# Kubernetes

Two equivalent deployment paths are provided:

1. **Helm** (`helm/taskboard`) — used for the graded deployment and GitOps.
2. **Raw manifests** (`kubernetes/`) — a readable reference for every object.

Do not apply both at the same time; they create the same object names.

## Objects

| Manifest | Objects |
| --- | --- |
| `namespace.yaml` | `taskboard` namespace |
| `configmap.yaml` | non-secret application settings |
| `secret.example.yaml` | example only; never commit a real Secret |
| `postgres.yaml` | Secret, PVC, Deployment, Service |
| `backend.yaml` | backend Deployment and Service |
| `frontend.yaml` | frontend Deployment and Service |
| `ingress.yaml` | Nginx Ingress for `/api` and `/` |
| `hpa.yaml` | CPU-based HPA, 2–6 replicas |

## Deploy with Helm

```bash
minikube start --driver=docker --cpus=4 --memory=6144 \
  --addons=ingress,metrics-server

# Build and make the images visible to the minikube node.
docker build -f docker/backend.Dockerfile -t taskboard-backend:local application/backend
docker build -f docker/frontend.Dockerfile -t taskboard-frontend:local application/frontend
minikube image load taskboard-backend:local
minikube image load taskboard-frontend:local
minikube image load postgres:16-alpine

helm upgrade --install taskboard helm/taskboard \
  --namespace taskboard --create-namespace \
  --set ingress.enabled=true \
  --set ingress.host=taskboard.local \
  --set hpa.enabled=true
```

## Verify

```bash
kubectl -n taskboard get pods,svc,ingress,hpa,pvc
kubectl -n taskboard rollout status deploy/taskboard-backend
kubectl -n taskboard rollout status deploy/taskboard-frontend
```

With the Docker driver the Ingress controller is exposed as a NodePort:

```bash
NODEPORT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -H 'Host: taskboard.local' "http://$(minikube ip):${NODEPORT}/"
curl -H 'Host: taskboard.local' "http://$(minikube ip):${NODEPORT}/api/tasks/stats"
```

## Design decisions

- **Startup probe** on the backend gives Alembic and PostgreSQL time to finish
  before liveness can restart the container.
- **Init container** waits for `pg_isready` so the backend does not crash-loop
  while PostgreSQL initialises its data directory.
- **Separate frontend and backend Deployments** allow the frontend to be scaled
  independently and keep the API image small.
- **Readiness uses `/ready`**, which performs a database query. A backend that
  cannot reach PostgreSQL is removed from Service endpoints.
- **HPA** targets 60% CPU against a `100m` request. The local load test scaled
  the backend from 2 to 6 replicas; see `screenshots/07-hpa/`.
- **Ingress** sends `/api` to the backend on port `8000` and everything else to
  the frontend on port `80`.

## Raw manifests

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/postgres.yaml
kubectl apply -f kubernetes/backend.yaml
kubectl apply -f kubernetes/frontend.yaml
kubectl apply -f kubernetes/ingress.yaml
kubectl apply -f kubernetes/hpa.yaml
```

`secret.example.yaml` is documentation only. The Helm chart creates the
PostgreSQL Secret from `values.yaml` for this classroom environment; production
should use an external secret manager or `kubectl create secret`.
