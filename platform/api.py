from flask import Flask, jsonify, request
import subprocess, json, os, glob, time

app = Flask(__name__)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENVS_DIR = os.path.join(BASE_DIR, "../envs")
LOGS_DIR = os.path.join(BASE_DIR, "../logs")
CREATE_SCRIPT = os.path.join(BASE_DIR, "create_env.sh")
DESTROY_SCRIPT = os.path.join(BASE_DIR, "destroy_env.sh")
OUTAGE_SCRIPT = os.path.join(BASE_DIR, "simulate_outage.sh")

def load_state(env_id):
    path = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(path): return None
    with open(path) as f: return json.load(f)

def all_envs():
    envs = []
    for f in glob.glob(os.path.join(ENVS_DIR, "*.json")):
        try:
            with open(f) as fp: envs.append(json.load(fp))
        except: pass
    return envs

@app.route("/")
def index():
    return jsonify({"status": "devops-sandbox api running", "version": "1.0.0"})

@app.route("/envs", methods=["POST"])
def create_env():
    body = request.get_json() or {}
    name = body.get("name")
    ttl = body.get("ttl", 1800)
    if not name: return jsonify({"error": "name is required"}), 400
    result = subprocess.run(["bash", CREATE_SCRIPT, name, str(ttl)], capture_output=True, text=True)
    if result.returncode != 0: return jsonify({"error": result.stderr}), 500
    env_id = None
    for line in result.stdout.splitlines():
        if line.strip().startswith("ID:"):
            env_id = line.split("ID:")[1].strip()
            break
    return jsonify(load_state(env_id) if env_id else {}), 201

@app.route("/envs", methods=["GET"])
def list_envs():
    now = int(time.time())
    envs = all_envs()
    for e in envs: e["ttl_remaining"] = max(0, e["created_at"] + e["ttl"] - now)
    return jsonify(envs), 200

@app.route("/envs/<env_id>", methods=["DELETE"])
def destroy_env(env_id):
    if not load_state(env_id): return jsonify({"error": "env not found"}), 404
    result = subprocess.run(["bash", DESTROY_SCRIPT, env_id], capture_output=True, text=True)
    if result.returncode != 0: return jsonify({"error": result.stderr}), 500
    return jsonify({"message": f"{env_id} destroyed"}), 200

@app.route("/envs/<env_id>/logs", methods=["GET"])
def get_logs(env_id):
    if not load_state(env_id): return jsonify({"error": "env not found"}), 404
    log_file = os.path.join(LOGS_DIR, env_id, "app.log")
    if not os.path.exists(log_file): return jsonify({"logs": []}), 200
    with open(log_file) as f: lines = f.readlines()
    return jsonify({"logs": lines[-100:]}), 200

@app.route("/envs/<env_id>/health", methods=["GET"])
def get_health(env_id):
    if not load_state(env_id): return jsonify({"error": "env not found"}), 404
    health_file = os.path.join(LOGS_DIR, env_id, "health.log")
    if not os.path.exists(health_file): return jsonify({"health": []}), 200
    with open(health_file) as f: lines = f.readlines()
    checks = []
    for line in lines[-10:]:
        try: checks.append(json.loads(line))
        except: checks.append({"raw": line.strip()})
    return jsonify({"health": checks}), 200

@app.route("/envs/<env_id>/outage", methods=["POST"])
def trigger_outage(env_id):
    if not load_state(env_id): return jsonify({"error": "env not found"}), 404
    body = request.get_json() or {}
    mode = body.get("mode")
    if not mode: return jsonify({"error": "mode is required"}), 400
    result = subprocess.run(["bash", OUTAGE_SCRIPT, "--env", env_id, "--mode", mode], capture_output=True, text=True)
    if result.returncode != 0: return jsonify({"error": result.stderr}), 500
    return jsonify({"message": result.stdout.strip()}), 200

if __name__ == "__main__":
    port = int(os.environ.get("API_PORT", 8000))
    app.run(host="0.0.0.0", port=port, debug=False)
