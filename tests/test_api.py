import time
import pytest
import requests

BASE = "http://localhost:5000"


@pytest.fixture
def created_env():
    r = requests.post(f"{BASE}/envs", json={"name": "api-test-env", "ttl": 120})
    assert r.status_code == 201
    env = r.json()
    yield env
    # cleanup after test
    requests.delete(f"{BASE}/envs/{env['id']}")


#  POST /envs
class TestCreateEnv:
    def test_create_returns_201(self):
        r = requests.post(f"{BASE}/envs", json={"name": "test-create", "ttl": 60})
        assert r.status_code == 201
        requests.delete(f"{BASE}/envs/{r.json()['id']}")

    def test_create_returns_env_id(self):
        r = requests.post(f"{BASE}/envs", json={"name": "test-id", "ttl": 60})
        assert "id" in r.json()
        requests.delete(f"{BASE}/envs/{r.json()['id']}")

    def test_create_returns_correct_name(self):
        r = requests.post(f"{BASE}/envs", json={"name": "test-name", "ttl": 60})
        assert r.json()["name"] == "test-name"
        requests.delete(f"{BASE}/envs/{r.json()['id']}")

    def test_create_missing_name_returns_400(self):
        r = requests.post(f"{BASE}/envs", json={"ttl": 60})
        assert r.status_code == 400

    def test_create_default_ttl(self):
        r = requests.post(f"{BASE}/envs", json={"name": "test-ttl"})
        assert r.json()["ttl"] == 1800
        requests.delete(f"{BASE}/envs/{r.json()['id']}")


#  GET /envs
class TestListEnvs:
    def test_list_returns_200(self):
        r = requests.get(f"{BASE}/envs")
        assert r.status_code == 200

    def test_list_returns_array(self):
        r = requests.get(f"{BASE}/envs")
        assert isinstance(r.json(), list)

    def test_list_contains_created_env(self, created_env):
        r = requests.get(f"{BASE}/envs")
        ids = [e["id"] for e in r.json()]
        assert created_env["id"] in ids

    def test_list_includes_ttl_remaining(self, created_env):
        r = requests.get(f"{BASE}/envs")
        env = next(e for e in r.json() if e["id"] == created_env["id"])
        assert "ttl_remaining" in env
        assert env["ttl_remaining"] > 0


#  DELETE /envs/:id 
class TestDestroyEnv:
    def test_destroy_returns_200(self):
        r = requests.post(f"{BASE}/envs", json={"name": "to-destroy", "ttl": 60})
        env_id = r.json()["id"]
        r = requests.delete(f"{BASE}/envs/{env_id}")
        assert r.status_code == 200

    def test_destroy_removes_from_list(self):
        r = requests.post(f"{BASE}/envs", json={"name": "to-remove", "ttl": 60})
        env_id = r.json()["id"]
        requests.delete(f"{BASE}/envs/{env_id}")
        r = requests.get(f"{BASE}/envs")
        ids = [e["id"] for e in r.json()]
        assert env_id not in ids

    def test_destroy_nonexistent_returns_404(self):
        r = requests.delete(f"{BASE}/envs/env-does-not-exist")
        assert r.status_code == 404


#  GET /envs/:id/logs
class TestGetLogs:
    def test_logs_returns_200(self, created_env):
        r = requests.get(f"{BASE}/envs/{created_env['id']}/logs")
        assert r.status_code == 200

    def test_logs_returns_list(self, created_env):
        r = requests.get(f"{BASE}/envs/{created_env['id']}/logs")
        assert "logs" in r.json()
        assert isinstance(r.json()["logs"], list)

    def test_logs_nonexistent_env_returns_404(self):
        r = requests.get(f"{BASE}/envs/env-does-not-exist/logs")
        assert r.status_code == 404

    def test_logs_max_100_lines(self, created_env):
        time.sleep(2)
        r = requests.get(f"{BASE}/envs/{created_env['id']}/logs")
        assert len(r.json()["logs"]) <= 100


#  GET /envs/:id/health
class TestGetHealth:
    def test_health_returns_200(self, created_env):
        r = requests.get(f"{BASE}/envs/{created_env['id']}/health")
        assert r.status_code == 200

    def test_health_returns_list(self, created_env):
        r = requests.get(f"{BASE}/envs/{created_env['id']}/health")
        assert "health" in r.json()
        assert isinstance(r.json()["health"], list)

    def test_health_nonexistent_env_returns_404(self):
        r = requests.get(f"{BASE}/envs/env-does-not-exist/health")
        assert r.status_code == 404

    def test_health_max_10_results(self, created_env):
        time.sleep(2)
        r = requests.get(f"{BASE}/envs/{created_env['id']}/health")
        assert len(r.json()["health"]) <= 10


#  POST /envs/:id/outage
class TestOutage:
    def test_outage_pause_returns_200(self, created_env):
        r = requests.post(
            f"{BASE}/envs/{created_env['id']}/outage",
            json={"mode": "pause"}
        )
        assert r.status_code == 200

    def test_outage_recover_returns_200(self, created_env):
        requests.post(
            f"{BASE}/envs/{created_env['id']}/outage",
            json={"mode": "pause"}
        )
        r = requests.post(
            f"{BASE}/envs/{created_env['id']}/outage",
            json={"mode": "recover"}
        )
        assert r.status_code == 200

    def test_outage_missing_mode_returns_400(self, created_env):
        r = requests.post(
            f"{BASE}/envs/{created_env['id']}/outage",
            json={}
        )
        assert r.status_code == 400

    def test_outage_nonexistent_env_returns_404(self):
        r = requests.post(
            f"{BASE}/envs/env-does-not-exist/outage",
            json={"mode": "crash"}
        )
        assert r.status_code == 404
