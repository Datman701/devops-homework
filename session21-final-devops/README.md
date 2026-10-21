# Session 21 — TaskBoard Final DevOps Project

An end-to-end delivery of the TaskBoard application: containerised locally,
tested and scanned in CI, published to GHCR, deployed to Kubernetes with Helm,
observed with Prometheus and Grafana, and reconciled by ArgoCD.

The application is based on the **TaskBoard reference** (`session21-python`),
not the earlier ClinicDesk capstone. All screenshots in this directory were
captured from the new local runs described below.

## Architecture

```text
                         ┌──────────────────────────────┐
                         │           GitHub             │
                         │  CI: test → SAST → SCA →     │
                         │  secrets → image scan → push │
                         └──────────────┬───────────────┘
                                        │ GHCR images (commit SHA)
                                        ▼
┌───────────────┐    Git      ┌──────────────────┐    reconcile    ┌─────────────────────┐
│  ArgoCD       │◀────────────│  Git repository  │───────────────▶│  Kubernetes/minikube │
│  Application  │             │  Helm chart      │                 │  namespace taskboard │
└───────────────┘             └──────────────────┘                 │  frontend ×2         │
                                                                   │  backend  ×2–6 (HPA) │
                                                                   │  postgres ×1 + PVC   │
                                                                   └──────────┬──────────┘
                                                                              │ /metrics
                                                                              ▼
                                                                   ┌─────────────────────┐
                                                                   │ Prometheus + Grafana│
                                                                   │ monitoring namespace│
                                                                   └─────────────────────┘
```

## Deliverable layout

```text
session21-final-devops/
├── application/          # TaskBoard backend, frontend, tests
├── docker/               # Dockerfiles and docker-compose.yml
├── kubernetes/           # raw namespace/configmap/secret/workload manifests
├── helm/taskboard/       # Helm chart used for the real deployment
├── terraform/            # AWS VPC + EKS, offline plan
├── .github/workflows/    # CI workflow (mirror; GitHub runs the root workflow)
├── security/             # Gitleaks and Trivy configuration
├── monitoring/           # Prometheus, Grafana, node-exporter, dashboards
├── gitops/               # ArgoCD Application
├── troubleshooting/      # broken-image and broken-service drills
├── screenshots/          # numbered evidence folders
└── README.md
```

> GitHub Actions only executes workflows in the repository-root
> `.github/workflows/` directory. The root workflow is
> `.github/workflows/s21-final.yml`; `session21-final-devops/.github/workflows/ci-cd.yml`
> is a mirror kept with the project for completeness.

## What was built

### Application

- FastAPI backend with health, readiness, metrics, CRUD, and stats endpoints.
- PostgreSQL 16 with an Alembic migration.
- React 19 + Vite frontend served by Nginx, proxying `/api` to the backend.
- 13 backend tests using an isolated SQLite database.
- Ruff, Bandit, pip-audit, npm build, and npm audit are clean.

### Containers

- Backend image runs as non-root UID 10001.
- Frontend uses a multi-stage Node build and an Nginx runtime.
- Compose stack includes PostgreSQL health checks and ordered startup.
- Local host ports are `13001` (frontend), `18000` (backend), and `15432`
  (PostgreSQL) to avoid clashing with other classroom stacks on this machine.

### Kubernetes

- Helm chart with backend, frontend, PostgreSQL, PVC, Secret, ConfigMap,
  Ingress, startup/readiness/liveness probes, and HPA.
- Raw manifests mirror the chart for readability.
- Ingress routes `/api` to `taskboard-backend:8000` and `/` to
  `taskboard-frontend:80`.
- Backend startup probe and a `pg_isready` init container prevent PostgreSQL
  startup races.
- HPA targets 60% CPU, min 2, max 6. A local load test scaled the backend from
  2 to 6 replicas (CPU reached 402% of request).

### Terraform

- Explicit AWS VPC, two AZs, public/private subnets, routes, security groups,
  IAM roles, EKS cluster, and managed node group.
- `terraform validate` succeeds and `terraform plan` renders **15 resources**
  offline.
- No AWS account is available, so **apply and destroy were not run**. No AWS
  resources were created.

### CI/CD and security

The root workflow `.github/workflows/s21-final.yml` runs:

```text
test (pytest, ruff, npm ci/build)
  ├── SAST (Bandit)
  ├── SCA (pip-audit, npm audit)
  └── secret scan (Gitleaks)
          └── build backend/frontend
                 └── Trivy HIGH/CRITICAL scans
                        └── security gate
                               └── push SHA-tagged images to GHCR
```

ArgoCD provides continuous delivery: the cluster is reconciled from Git, so
there is no kubeconfig-based deploy job holding cluster credentials in GitHub.
The chart images are updated to the CI-built commit SHA in
`gitops/application.yaml`.

Verified in GitHub Actions run
[`39607718459`](https://github.com/Datman701/devops-homework/actions/runs/39607718459)
on commit `302d6de`: all six jobs passed, and both images were published to
GHCR with the full commit SHA and a short-SHA tag.

The local application sets `ingress.enabled=false` because ingress-nginx is
exposed as a NodePort here and ArgoCD would otherwise wait for a LoadBalancer
address. The Helm chart and raw manifests still contain the Ingress; the
Kubernetes evidence was captured with it enabled.

### Monitoring

- Prometheus scrapes `taskboard-backend.taskboard.svc.cluster.local:8000/metrics`.
- All targets reported `up`.
- Grafana dashboard covers request totals, status and method breakdowns, p95
  latency, and the 5xx error ratio.
- TaskBoard-specific alert rules are loaded alongside node rules.

## Reproduce locally

### 1. Tests and application

```bash
cd application/backend
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest -v
.venv/bin/ruff check app tests
.venv/bin/bandit -r app -ll
.venv/bin/pip-audit -r requirements.txt

cd ../frontend
npm ci
npm run build
npm audit --audit-level=high
```

### 2. Docker Compose

```bash
cd session21-final-devops
docker compose -f docker/docker-compose.yml -p taskboard up -d --build
curl -s http://localhost:18000/health
curl -s http://localhost:18000/api/tasks/stats
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:13001/
```

### 3. Kubernetes and Helm

```bash
minikube start --driver=docker --cpus=4 --memory=6144 \
  --addons=ingress,metrics-server

# The scratch images must be visible to the minikube node.
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

kubectl -n taskboard get pods,svc,ingress,hpa,pvc
```

With the Docker driver, reach the Ingress through its NodePort:

```bash
NODEPORT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -H 'Host: taskboard.local' "http://$(minikube ip):${NODEPORT}/api/tasks/stats"
```

### 4. Monitoring

See [`monitoring/README.md`](monitoring/README.md). Short version:

```bash
kubectl apply -f monitoring/namespace.yaml
kubectl apply -n monitoring -f monitoring/
kubectl -n monitoring port-forward svc/prometheus 19090:9090
kubectl -n monitoring port-forward svc/grafana 13002:3000
```

### 5. GitOps

See [`gitops/README.md`](gitops/README.md). Short version:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f gitops/application.yaml
kubectl -n argocd get application taskboard
```

### 6. Troubleshooting drills

See [`troubleshooting/README.md`](troubleshooting/README.md). Both drills were
run locally:

- deliberately bad image → `ImagePullBackOff` → corrected image → `Running`
- Service selector with no matching Pods → Endpoints `<none>` → corrected
  selector → two backend endpoints and `/health` returns `UP`

## Evidence

Screenshots are grouped by concern under [`screenshots/`](screenshots/):

| Folder | Evidence |
| --- | --- |
| `01-application/` | backend checks, frontend build, API smoke test, UI |
| `02-docker/` | Compose services and logs |
| `03-tests/` | pytest, Ruff, Bandit, pip-audit |
| `04-ci-cd/` | GitHub Actions run, jobs, GHCR images |
| `05-terraform/` | init/fmt/validate and plan summary |
| `06-kubernetes/` | pods/services/ingress, Helm status, Ingress access |
| `07-hpa/` | HPA scale-out from 2 to 6 |
| `08-monitoring/` | Prometheus targets, Grafana dashboard |
| `09-gitops/` | ArgoCD application Synced/Healthy |
| `10-troubleshooting/` | ImagePullBackOff and empty-Endpoints drills |
