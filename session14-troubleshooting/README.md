# Session 14: Kubernetes Troubleshooting

## Screenshots

### Task 1 — Troubleshooting commands

#### 1. kubectl get (default, -o wide, custom-columns)

![kubectl get](01-commands/01-kubectl-get.png)

#### 2. kubectl describe

![kubectl describe](01-commands/02-kubectl-describe.png)

#### 3. kubectl logs

![kubectl logs](01-commands/03-kubectl-logs-exec.png)

#### 4. kubectl exec

![kubectl exec](01-commands/04-kubectl-exec.png)

#### 5. kubectl events + explain + top

![kubectl events explain top](01-commands/05-kubectl-events-explain-top.png)

### Task 2 — Common issues

#### 1. CrashLoopBackOff — broken

![CrashLoopBackOff broken](02-common-issues/01-crashloop-broken.png)

#### 2. CrashLoopBackOff — fixed

![CrashLoopBackOff fixed](02-common-issues/02-crashloop-fixed.png)

#### 3. ImagePullBackOff — broken

![ImagePullBackOff broken](02-common-issues/03-imagepull-broken.png)

#### 4. ImagePullBackOff — fixed

![ImagePullBackOff fixed](02-common-issues/04-imagepull-fixed.png)

#### 5. ErrImagePull — broken

![ErrImagePull broken](02-common-issues/05-errimage-broken.png)

#### 6. ErrImagePull — fixed

![ErrImagePull fixed](02-common-issues/06-errimage-fixed.png)

#### 7. Pending (unsatisfiable requests) — broken

![Pending broken](02-common-issues/07-pending-broken.png)

#### 8. Pending — fixed

![Pending fixed](02-common-issues/08-pending-fixed.png)

#### 9. Service selector mismatch — broken

![Service connectivity broken](02-common-issues/09-service-broken.png)

#### 10. Service selector mismatch — fixed

![Service connectivity fixed](02-common-issues/10-service-fixed.png)

#### 11. DNS resolution test

![DNS test](02-common-issues/11-dns-broken.png)

#### 12. DNS resolution verified

![DNS fixed](02-common-issues/12-dns-fixed.png)

#### 13. Pod networking (NetworkPolicy) — fixed

![Pod networking fixed](02-common-issues/13-networking-fixed.png)

#### 14. ConfigMap configuration — fixed

![Configuration fixed](02-common-issues/14-config-fixed.png)

### Task 3 — Mini project

#### 1. Broken deployment deployed (liveness path + selector faults)

![Mini project broken](03-mini-project/01-mini-01-broken-deployed.png)

#### 2. Root cause identified

![Mini project diagnosis](03-mini-project/02-mini-02-diagnose.png)

#### 3. Fixed — endpoints healthy

![Mini project fixed](03-mini-project/03-mini-03-fixed.png)
