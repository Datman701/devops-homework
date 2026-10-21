# DevSecOps Pipeline

Security checks run in GitHub Actions and can be reproduced locally.

| Gate | Tool | Scope | Result |
| --- | --- | --- | --- |
| SAST | Bandit 1.8 | `application/backend/app` | no issues |
| Python SCA | pip-audit 2.7.3 | `requirements.txt` | no known vulnerabilities |
| Node SCA | `npm audit` | `application/frontend` | 0 vulnerabilities |
| Secret scan | Gitleaks | repository history | configured with a classroom allowlist |
| Image scan | Trivy | backend and frontend images | 0 HIGH/CRITICAL after fixes |
| Security gate | GitHub Actions | all of the above | blocks image publication |

## Bandit

```bash
cd application/backend
.venv/bin/bandit -r app -ll -f screen
```

## pip-audit

The runtime set was upgraded to remove the Starlette advisories found in the
reference pins. Current pins:

```text
fastapi==0.156.8
starlette==1.3.1
prometheus-fastapi-instrumentator==8.1.0
```

`pip-audit -r requirements.txt` now reports `No known vulnerabilities found`.

## npm audit

```bash
cd application/frontend
npm ci
npm audit --audit-level=high
```

The lockfile is committed. The audit reports 0 vulnerabilities.

## Gitleaks

`security/.gitleaks.toml` extends the default rule set and allows only the
deliberate classroom PostgreSQL password used by Compose and Helm. Real
credentials are never committed; the Terraform stack reads them from the
standard AWS credential chain.

```bash
gitleaks detect --config security/.gitleaks.toml --source .
```

## Trivy

The frontend runtime installs Alpine security updates during the image build:

```dockerfile
FROM nginx:1.29-alpine
RUN apk upgrade --no-cache
```

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed taskboard-backend:local
trivy image --severity HIGH,CRITICAL --ignore-unfixed taskboard-frontend:local
```

Both images report zero HIGH/CRITICAL findings in the final state. The CI job
uses `exit-code: 1`, so a new HIGH or CRITICAL finding fails the build before
the image is pushed to GHCR.

## Gate order

```text
test + lint
   └── SAST
   └── SCA
   └── secret scan
          └── build images
                 └── Trivy image scans
                        └── security gate
                               └── push to GHCR
```

The `images` job declares `needs: [test, sast, sca, secret-scan]`, and the
`security-gate` job declares `needs: [images]`. A failure at any earlier gate
stops publication.
