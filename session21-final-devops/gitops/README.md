# GitOps — ArgoCD

ArgoCD is the continuous-delivery controller for TaskBoard. The cluster state
is defined in Git:

- chart: `session21-final-devops/helm/taskboard`
- image tags: the commit SHA published by the CI workflow
- destination: the `taskboard` namespace

Nothing is deployed by hand after the initial bootstrap. ArgoCD watches the
repository and reconciles the cluster to match it (`Synced` / `Healthy`). With
`selfHeal: true`, a manual `kubectl edit` that drifts from Git is reverted
automatically; with `prune: true`, resources removed from the chart are removed
from the cluster.

For the local minikube demo the Application passes `ingress.enabled=false`.
The ingress-nginx controller is exposed as a NodePort, so it does not publish a
LoadBalancer address; keeping the Ingress in the Application would leave
ArgoCD's Ingress health check at `Progressing`. The Helm chart and raw manifests
still contain the Ingress and are exercised in the Kubernetes evidence.

## Bootstrap

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f gitops/application.yaml
```

## Access the UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Open <https://localhost:8080> and sign in as `admin`.

## Verify

```bash
kubectl get application -n argocd taskboard
kubectl get pods -n taskboard
```
