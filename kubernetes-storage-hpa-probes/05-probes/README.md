## Screenshots

### 1. Liveness probe — healthy pod, 0 restarts

![Liveness probe healthy](01-liveness-probe-healthy.png)

### 2. Readiness probe — healthy pod, endpoints populated

![Readiness probe healthy](02-readiness-probe-healthy.png)

### 3. Readiness probe failing — 0/1 Running, 0 restarts, empty endpoints

![Readiness probe failing](03-readiness-probe-failing.png)

### 4. Liveness probe failing — CrashLoopBackOff, restarts climbing, 404 events

![Liveness probe failing](04-liveness-probe-failing.png)

### 5. Startup probe — all three probes configured on one pod

![Startup probe](05-startup-probe.png)