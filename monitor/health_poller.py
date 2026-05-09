import os
import json
import time
import glob
import requests

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENVS_DIR = os.path.join(BASE_DIR, "../envs")
LOGS_DIR = os.path.join(BASE_DIR, "../logs")

POLL_INTERVAL = 30
FAILURE_THRESHOLD = 3

failure_counts = {}


def load_all_envs():
    files = glob.glob(os.path.join(ENVS_DIR, "*.json"))
    envs = []
    for f in files:
        with open(f) as fp:
            try:
                envs.append(json.load(fp))
            except json.JSONDecodeError:
                continue
    return envs


def update_status(env_id, status):
    state_file = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(state_file):
        return
    with open(state_file) as f:
        state = json.load(f)
    state["status"] = status
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, state_file)


def write_health_log(env_id, timestamp, http_status, latency, note=""):
    log_dir = os.path.join(LOGS_DIR, env_id)
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "health.log")
    line = f"[{timestamp}] status={http_status} latency={latency:.2f}ms {note}\n"
    with open(log_file, "a") as f:
        f.write(line)


def poll_env(env):
    env_id = env["id"]
    port = env["port"]
    url = f"http://localhost:{port}/health"
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

    try:
        start = time.time()
        response = requests.get(url, timeout=5)
        latency = (time.time() - start) * 1000
        http_status = response.status_code

        if http_status == 200:
            failure_counts[env_id] = 0
            write_health_log(env_id, timestamp, http_status, latency)
            update_status(env_id, "running")
        else:
            raise Exception(f"non-200 status: {http_status}")

    except Exception as e:
        latency = 0
        failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
        count = failure_counts[env_id]
        note = f"FAIL ({count}/{FAILURE_THRESHOLD}) — {str(e)}"
        write_health_log(env_id, timestamp, 0, latency, note)

        if count >= FAILURE_THRESHOLD:
            print(f"[{timestamp}] WARNING: {env_id} is DEGRADED after {count} failures")
            update_status(env_id, "degraded")


def main():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Health poller started")
    while True:
        envs = load_all_envs()
        for env in envs:
            poll_env(env)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
