# Session 17: CI/CD & DevSecOps

Pipeline: `Unit Tests` → (`SAST` + `SCA` + `Secret Scanning` in parallel) → `Docker Build` → `Image Scan` → `Push GHCR`.
Every security job is a hard gate — a failure stops the pipeline before the image is published.

Workflow: `.github/workflows/s17-devsecops.yml` (mirror in `01-app/.github/workflows/devsecops.yml`).
Application: `01-app/` (Flask dashboard, Dockerfile, `k8s/` manifests, pytest suite).
Real run: <https://github.com/Datman701/devops-homework/actions/runs/37663079981>

## Screenshots

### Local security verification

#### 1. Unit tests with coverage — 8 passed

![Unit tests](02-screenshots/01-s17-01-tests.png)

#### 2. SAST — bandit static analysis

![SAST bandit](02-screenshots/02-s17-02-sast.png)

#### 3. SCA (pip-audit) and secret scanning — both clean

![SCA and secret scan](02-screenshots/03-s17-03-sca-secrets.png)

#### 4. Container image scanning — Trivy, 44 HIGH findings

![Trivy image scan](02-screenshots/04-s17-04-trivy-image-scan.png)

#### 5. Security gate — CRITICAL threshold blocks publish

![Security gate](02-screenshots/05-s17-05-security-gate.png)

#### 6. Kubernetes deployment — app serving real traffic

![Kubernetes deployment](02-screenshots/06-s17-06-k8s-deployment.png)

### Real GitHub Actions run

#### 7. Workflow runs list

![Actions runs list](02-screenshots/07-s17-07-actions-runs-list.png)

#### 8. All seven gated jobs green, gate fan-out visible

![Seven gated jobs](02-screenshots/08-s17-08-seven-gated-jobs-green.png)

#### 9. Image Scan (Trivy) job steps

![Trivy job steps](02-screenshots/09-s17-09-trivy-job-steps.png)

#### 10. Image published to GHCR

![GHCR package](02-screenshots/10-s17-10-ghcr-package.png)
