# Docker

The local stack runs PostgreSQL, the FastAPI backend, and the React frontend in
three containers. The Dockerfiles live in this directory so the repository
matches the final-project layout; the build contexts remain the application
directories.

| File | Purpose |
| --- | --- |
| `backend.Dockerfile` | Python 3.12 slim, non-root UID 10001, Alembic then Uvicorn |
| `frontend.Dockerfile` | Node 22 build stage, Nginx 1.29 runtime |
| `docker-compose.yml` | PostgreSQL + backend + frontend with health checks |

## Run

```bash
cd session21-final-devops
docker compose -f docker/docker-compose.yml -p taskboard up -d --build
docker compose -f docker/docker-compose.yml -p taskboard ps
```

Host ports are deliberately non-default because this machine already runs other
classroom stacks:

| Service | Host port | Container port |
| --- | --- | --- |
| Frontend | `13001` | `80` |
| Backend | `18000` | `8000` |
| PostgreSQL | `15432` | `5432` |

```bash
curl -s http://localhost:18000/health
curl -s http://localhost:18000/ready
curl -s http://localhost:18000/api/tasks/stats
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:13001/
```

## Health and startup order

- PostgreSQL has a `pg_isready` health check.
- The backend waits for PostgreSQL (`depends_on: condition: service_healthy`),
  then runs Alembic and starts Uvicorn.
- The frontend waits for the backend health check before starting.
- The backend health check calls `/health` from inside the container.

## Image hardening

- Backend runs as UID `10001`, not root.
- Frontend build uses `npm ci` from the committed lockfile.
- The Nginx runtime stage runs `apk upgrade --no-cache` to pick up Alpine security
  fixes. Trivy reports zero HIGH/CRITICAL findings for the resulting image.
- No credentials are baked into either image. `DATABASE_URL` is supplied at
  runtime.

## Stop and clean up

```bash
docker compose -f docker/docker-compose.yml -p taskboard down
docker compose -f docker/docker-compose.yml -p taskboard down -v
```

The second command also removes the PostgreSQL volume.
