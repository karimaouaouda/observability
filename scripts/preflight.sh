#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
failures=0
docker_ready=0

ok() { printf 'OK: %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

if ! command -v docker >/dev/null 2>&1; then
  fail "Docker is not installed or not on PATH"
else
  ok "Docker is installed"
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose is available"
  else
    fail "Docker Compose v2 is unavailable"
  fi
  if docker info >/dev/null 2>&1; then
    docker_ready=1
    ok "Docker daemon is reachable"
  else
    fail "Docker daemon is not reachable"
  fi
fi

if command -v curl >/dev/null 2>&1; then
  ok "curl is available for post-deployment verification"
else
  fail "curl is required by scripts/verify.sh"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env is missing; copy .env.example and restore the existing Grafana values"
else
  ok ".env exists"
fi

env_value() {
  local key=$1 default=$2 value
  value=$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE" 2>/dev/null || true)
  value=${value%\"}; value=${value#\"}; value=${value%\'}; value=${value#\'}
  printf '%s' "${value:-$default}"
}

GRAFANA_DATA_VOLUME=$(env_value GRAFANA_DATA_VOLUME "")
GRAFANA_IMAGE=$(env_value GRAFANA_IMAGE "grafana/grafana:13.2.2")
GRAFANA_PORT=$(env_value GRAFANA_PORT "3011")
PROMETHEUS_PORT=$(env_value PROMETHEUS_PORT "9090")
LOKI_PORT=$(env_value LOKI_PORT "3100")

for file in compose.yml prometheus/prometheus.yml prometheus/targets/applications.yml \
  prometheus/targets/hosts.yml loki/loki.yml; do
  [[ -f "$ROOT_DIR/$file" ]] && ok "$file exists" || fail "$file is missing"
done

if [[ -z "${GRAFANA_DATA_VOLUME:-}" ]]; then
  fail "GRAFANA_DATA_VOLUME is not configured"
elif (( docker_ready == 1 )); then
  if docker volume inspect "$GRAFANA_DATA_VOLUME" >/dev/null 2>&1; then
    ok "existing Grafana volume '$GRAFANA_DATA_VOLUME' exists"
  else
    fail "external Grafana volume '$GRAFANA_DATA_VOLUME' does not exist; it was not created"
  fi
fi

if (( docker_ready == 1 )); then
  if docker network inspect observability >/dev/null 2>&1; then
    ok "existing Docker network 'observability' exists"
  else
    fail "existing Docker network 'observability' does not exist; verify the old deployment"
  fi
fi

if (( docker_ready == 1 )) && docker inspect grafana >/dev/null 2>&1; then
  current_mount=$(docker inspect grafana --format '{{range .Mounts}}{{if eq .Destination "/var/lib/grafana"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true)
  current_image=$(docker inspect grafana --format '{{.Config.Image}}' 2>/dev/null || true)
  current_project=$(docker inspect grafana --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || true)
  if [[ -n "${GRAFANA_DATA_VOLUME:-}" && "$current_mount" == "$GRAFANA_DATA_VOLUME" ]]; then
    ok "existing grafana container uses '$GRAFANA_DATA_VOLUME' at /var/lib/grafana"
  elif [[ -n "$current_mount" ]]; then
    fail "existing grafana container uses '$current_mount', not '$GRAFANA_DATA_VOLUME'"
  else
    fail "could not verify the existing grafana /var/lib/grafana named-volume mount"
  fi
  if [[ "$current_image" == "$GRAFANA_IMAGE" ]]; then
    ok "existing grafana image '$current_image' is preserved"
  else
    fail "existing grafana image is '$current_image', but .env configures '$GRAFANA_IMAGE'"
  fi
  if [[ "$current_project" == "observability" ]]; then
    ok "grafana already belongs to the observability Compose project"
  else
    warn "existing container 'grafana' must be stopped and renamed as documented before the first start"
  fi
fi

check_port() {
  local port=$1 service=$2 owners
  (( docker_ready == 1 )) || return 0
  owners=$(docker ps --format '{{.Names}} {{.Ports}}' | awk -v p=":${port}->" 'index($0,p) {print $1}')
  if [[ -z "$owners" ]]; then
    ok "host port $port is available"
  elif [[ "$owners" == *"$service"* ]]; then
    warn "port $port is occupied by the expected $service container"
  else
    fail "host port $port is occupied by: $owners"
  fi
}

check_port "$GRAFANA_PORT" grafana
check_port "$PROMETHEUS_PORT" prometheus
check_port "$LOKI_PORT" loki

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && [[ -f "$ENV_FILE" ]]; then
  if (cd "$ROOT_DIR" && docker compose config >/dev/null); then
    ok "docker compose config succeeds"
  else
    fail "docker compose config failed"
  fi
fi

if (( failures > 0 )); then
  printf '\nPreflight failed with %d issue(s). Nothing was changed.\n' "$failures" >&2
  exit 1
fi

printf '\nPreflight passed. No resources were changed.\n'
