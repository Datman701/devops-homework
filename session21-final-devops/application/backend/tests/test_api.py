def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "UP"}


def test_readiness_checks_database(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "READY"}


def test_root_reports_service_and_docs(client):
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["service"] == "TaskBoard API"
    assert body["docs"] == "/docs"


def test_create_task(client):
    response = client.post(
        "/api/tasks",
        json={
            "title": "Deploy application",
            "priority": "HIGH",
            "assignee": "Student",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Deploy application"
    assert body["status"] == "TODO"
    assert body["priority"] == "HIGH"


def test_create_task_requires_title(client):
    response = client.post("/api/tasks", json={"description": "missing title"})
    assert response.status_code == 422


def test_list_tasks(client, task):
    response = client.get("/api/tasks")
    assert response.status_code == 200
    assert any(item["id"] == task["id"] for item in response.json())


def test_get_task(client, task):
    response = client.get(f"/api/tasks/{task['id']}")
    assert response.status_code == 200
    assert response.json()["id"] == task["id"]


def test_get_missing_task_returns_404(client):
    response = client.get("/api/tasks/999999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"


def test_update_task_status(client, task):
    response = client.put(
        f"/api/tasks/{task['id']}",
        json={"status": "IN_PROGRESS"},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "IN_PROGRESS"


def test_stats_are_aggregated(client, task):
    client.post(
        "/api/tasks",
        json={"title": "Write runbook", "priority": "LOW", "status": "DONE"},
    )
    response = client.get("/api/tasks/stats")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] >= 2
    assert body["todo"] >= 1
    assert body["done"] >= 1


def test_delete_task(client, task):
    response = client.delete(f"/api/tasks/{task['id']}")
    assert response.status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_metrics_endpoint(client):
    client.get("/health")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text


def test_task_status_can_transition_across_all_values(client, task):
    for status in ("IN_PROGRESS", "DONE", "TODO"):
        response = client.put(f"/api/tasks/{task['id']}", json={"status": status})
        assert response.status_code == 200
        assert response.json()["status"] == status
