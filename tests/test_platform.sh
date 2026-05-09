#!/bin/bash
set -euo pipefail

BASE_DIR="$(dirname "$0")/.."
CREATE="$BASE_DIR/platform/create_env.sh"
DESTROY="$BASE_DIR/platform/destroy_env.sh"
ENVS_DIR="$BASE_DIR/envs"
LOGS_DIR="$BASE_DIR/logs"
NGINX_CONF_DIR="$BASE_DIR/nginx/conf.d"

PASS=0
FAIL=0

log() { echo "[TEST] $1"; }
pass() { echo "   $1"; PASS=$((PASS + 1)); }
fail() { echo "   $1"; FAIL=$((FAIL + 1)); }

#  create env
log "Test 1: create environment"
OUTPUT=$(bash "$CREATE" test-env 60)
ENV_ID=$(echo "$OUTPUT" | grep "ID:" | awk '{print $2}')

if [[ -n "$ENV_ID" ]]; then
  pass "create_env.sh returned an env ID: $ENV_ID"
else
  fail "create_env.sh did not return an env ID"
  exit 1
fi

# 
log "Test 2: state file written"
if [[ -f "$ENVS_DIR/$ENV_ID.json" ]]; then
  pass "state file exists at envs/$ENV_ID.json"
else
  fail "state file missing"
fi

#  state file is valid JSON
log "Test 3: state file is valid JSON"
if jq empty "$ENVS_DIR/$ENV_ID.json" 2>/dev/null; then
  pass "state file is valid JSON"
else
  fail "state file is not valid JSON"
fi

#  Docker container running
log "Test 4: Docker container is running"
if docker ps --filter "label=sandbox.env=$ENV_ID" --format "{{.Names}}" | grep -q "$ENV_ID"; then
  pass "container $ENV_ID is running"
else
  fail "container $ENV_ID not found"
fi

# Docker network exists 
log "Test 5: Docker network created"
if docker network ls --format "{{.Name}}" | grep -q "$ENV_ID"; then
  pass "network $ENV_ID exists"
else
  fail "network $ENV_ID not found"
fi

# Nginx config written
log "Test 6: Nginx config written"
if [[ -f "$NGINX_CONF_DIR/$ENV_ID.conf" ]]; then
  pass "nginx config exists at nginx/conf.d/$ENV_ID.conf"
else
  fail "nginx config missing"
fi

# log directory created
log "Test 7: log directory created"
if [[ -d "$LOGS_DIR/$ENV_ID" ]]; then
  pass "log directory exists at logs/$ENV_ID/"
else
  fail "log directory missing"
fi

#  Nginx responds 
log "Test 8: Nginx default route responds"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80)
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "Nginx responded with 200"
else
  fail "Nginx responded with $HTTP_CODE"
fi

# API list envs 
log "Test 9: API GET /envs returns env"
API_RESPONSE=$(curl -s http://localhost:5000/envs)
if echo "$API_RESPONSE" | jq -e ".[] | select(.id == \"$ENV_ID\")" > /dev/null 2>&1; then
  pass "API returned env $ENV_ID in list"
else
  fail "API did not return env $ENV_ID"
fi

# Test 10: destroy env 
log "Test 10: destroy environment"
bash "$DESTROY" "$ENV_ID"

if [[ ! -f "$ENVS_DIR/$ENV_ID.json" ]]; then
  pass "state file removed after destroy"
else
  fail "state file still exists after destroy"
fi

if ! docker ps -a --filter "label=sandbox.env=$ENV_ID" --format "{{.Names}}" | grep -q "$ENV_ID"; then
  pass "container removed after destroy"
else
  fail "container still exists after destroy"
fi

if [[ ! -f "$NGINX_CONF_DIR/$ENV_ID.conf" ]]; then
  pass "nginx config removed after destroy"
else
  fail "nginx config still exists after destroy"
fi

if [[ -d "$LOGS_DIR/archived/$ENV_ID" ]]; then
  pass "logs archived after destroy"
else
  fail "logs not archived after destroy"
fi


echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "Some tests failed."
  exit 1
fi
