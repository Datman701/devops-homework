# Troubleshooting Drills

Two deliberately broken manifests reproduce the most common Kubernetes
failures. Each drill records the symptom, the diagnostic command and the fix.

## 1. ImagePullBackOff

```bash
kubectl apply -f troubleshooting/broken-image.yaml
kubectl -n taskboard get pods
kubectl -n taskboard describe pod -l app=broken-image
kubectl apply -f troubleshooting/fixed-image.yaml
kubectl -n taskboard rollout status deploy/taskboard-broken-image
kubectl delete -f troubleshooting/fixed-image.yaml
```

Symptom: the pod stays in `ImagePullBackOff` because
`ghcr.io/example/taskboard-backend:does-not-exist` cannot be pulled.

Fix: point the Deployment at an image that exists
(`taskboard-backend:local` in the local lab) and verify the rollout.

## 2. Service has no endpoints

```bash
kubectl apply -f troubleshooting/broken-service.yaml
kubectl -n taskboard get endpoints broken-service
kubectl apply -f troubleshooting/fixed-service.yaml
kubectl -n taskboard get endpoints broken-service
kubectl -n taskboard port-forward svc/broken-service 18082:8080
curl -s http://localhost:18082/health
kubectl delete -f troubleshooting/fixed-service.yaml
```

Symptom: `kubectl get endpoints` shows `<none>` and port-forwarding to the
Service fails or returns no response.

Root cause: the Service selector is `app=label-that-does-not-exist`, which
matches no Pods.

Fix: select `app=taskboard-backend` and target port `8000`, then confirm that
the EndpointSlice contains both backend pod IPs.
