# TaskBoard Application

TaskBoard is a small full-stack task tracker used as the workload for the final
DevOps project. It is deliberately simple: the interesting part of this
repository is everything around the application — containers, Kubernetes,
Terraform, security scanning, monitoring, and GitOps.

## Stack

| Layer | Technology |
| --- | --- |
| Backend | Python 3.12, FastAPI, SQLAlchemy 2, Alembic, Uvicorn |
| Database | PostgreSQL 16 |
| Frontend | React 19, Vite 8, served by Nginx |
| Metrics | `prometheus-fastapi-instrumentator` on `/metrics` |

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/` | Service name and docs link |
| `GET` | `/health` | Liveness probe |
| `GET` | `/ready` | Readiness probe; executes a database query |
| `GET` | `/metrics` | Prometheus metrics |
| `GET` | `/api/tasks` | List tasks, newest first |
| `POST` | `/api/tasks` | Create a task |
| `GET` | `/api/tasks/{id}` | Read one task |
| `PUT` | `/api/tasks/{id}` | Update fields supplied in the body |
| `DELETE` | `/api/tasks/{id}` | Delete a task |
| `GET` | `/api/tasks/stats` | Counts by status |

Task status values are `TODO`, `IN_PROGRESS`, and `DONE`. Priority values are
`LOW`, `MEDIUM`, and `HIGH`.

## Backend layout

```text
backend/
├── alembic/                 # schema migration
├── app/
│   ├── config.py            # pydantic-settings configuration
│   ├── db.py                # SQLAlchemy engine/session
│   ├── main.py              # FastAPI routes and probes
│   ├── models.py            # Task ORM model
│   └── schemas.py           # request/response models
├── tests/
│   ├── conftest.py          # isolated SQLite test database
│   └── test_api.py          # API and probe tests
├── requirements.txt
└── requirements-dev.txt
```

The container runs `alembic upgrade head` before starting Uvicorn. Tests use a
throwaway SQLite database, so they never need PostgreSQL.

## Local backend

```bash
cd application/backend
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest -v
.venv/bin/ruff check app tests
.venv/bin/bandit -r app -ll
.venv/bin/pip-audit -r requirements.txt
DATABASE_URL=sqlite:///./dev.db .venv/bin/uvicorn app.main:app --reload
```

## Local frontend

```bash
cd application/frontend
npm ci
npm run build
npm run dev        # http://localhost:5173
```

The production Nginx config proxies `/api/` and `/health` to the Kubernetes
Service `taskboard-backend:8000`. Docker Compose gives the backend container the
same network alias, so one config works in both environments.

## Evidence

The application was verified locally with:

- `13 passed` in pytest
- Ruff check and format check clean
- Bandit: no issues
- pip-audit: no known vulnerabilities
- `npm ci`, `npm run build`, and `npm audit`: no vulnerabilities
