import os
from pathlib import Path

# The app reads DATABASE_URL at import time. Point it at a throwaway SQLite
# file so the tests never touch the PostgreSQL database used by Docker/K8s.
TEST_DB = Path(__file__).resolve().parent.parent / "test.db"
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB}"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def database():
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)
    engine.dispose()
    TEST_DB.unlink(missing_ok=True)


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def task(client):
    response = client.post(
        "/api/tasks",
        json={
            "title": "Configure production ingress",
            "description": "Route /api to the backend",
            "priority": "HIGH",
            "assignee": "DevOps",
        },
    )
    assert response.status_code == 201
    return response.json()
