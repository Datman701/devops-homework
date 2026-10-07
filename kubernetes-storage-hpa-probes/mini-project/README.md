## Screenshots

### 1. Namespace + PVC bound to a PV

![Namespace and PVC](01-namespace-and-pvc.png)

### 2. Deployment + Service — 2 ready Pods, endpoints populated

![Deployment and service](02-deployment-and-service.png)

### 3. All three probes configured on the Deployment

![Probes configured](03-all-three-probes.png)

### 4. HPA metrics live — conditions all True

![HPA metrics and conditions](04-hpa-metrics-and-conditions.png)

### 5. Data survives pod deletion — PVC persists

![Data persists across pod replacement](05-data-outlives-pod-deletion.png)