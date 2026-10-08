# Session 16: CI/CD & GitHub Actions

Pipeline: `lint` → `test` → `docker-build` → `push` (GHCR).

Workflow definition: `.github/workflows/s16-ci.yml` (mirror copy in `01-app/.github/workflows/ci.yml`).
Application: `01-app/` (calculator + pytest + Dockerfile).
Real run: <https://github.com/Datman701/devops-homework/actions/runs/37660905101>

## Screenshots

### 1. Lint and test locally (flake8 gate + pytest with coverage)

![flake8 and pytest](02-screenshots/01-s16-01-lint-and-test.png)

### 2. Docker build and container smoke test

![docker build and run](02-screenshots/02-s16-02-docker-build.png)

### 3. GitHub Actions — workflow runs list

![Actions runs list](02-screenshots/03-s16-03-github-actions-runs-list.png)

### 4. Run summary — all four jobs green, job graph with timings

![Run summary and job graph](02-screenshots/04-s16-04-run-summary-job-graph.png)

### 5. Run Tests job — every step passed

![Run Tests job steps](02-screenshots/05-s16-05-run-tests-job-steps.png)


### 6. Image published to GHCR

![GHCR package](02-screenshots/07-s16-07-ghcr-package.png)
