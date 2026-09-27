#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

ok() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

cd "$ROOT_DIR"

env_value() {
  local key=$1 default=$2 value
  value=$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' .env 2>/dev/null || true)
  value=${value%\"}; value=${value#\"}; value=${value%\'}; value=${value#\'}
  printf '%s' "${value:-$default}"
}

GRAFANA_PORT=$(env_value GRAFANA_PORT "3011")
PROMETHEUS_PORT=$(env_value PROMETHEUS_PORT "9090")
LOKI_PORT=$(env_value LOKI_PORT "3100")

for service in grafana prometheus loki; do
  if [[ "$(docker compose ps --status running --services "$service" 2>/dev/null)" == "$service" ]]; then
    ok "$service container is running"
  else
    fail "$service container is not running"
  fi
done

check_http() {
  local name=$1 url=$2
  if curl --fail --silent --show-error --max-time 10 "$url" >/dev/null; then
    ok "$name responds at $url"
  else
    fail "$name did not respond at $url"
  fi
}

check_http Grafana "http://127.0.0.1:${GRAFANA_PORT}/api/health"
check_http Prometheus "http://127.0.0.1:${PROMETHEUS_PORT}/-/healthy"
check_http Loki "http://127.0.0.1:${LOKI_PORT}/ready"

if docker compose exec -T grafana sh -c 'wget -qO- http://prometheus:9090/-/healthy >/dev/null'; then
  ok "Grafana can resolve and reach prometheus:9090"
else
  fail "Grafana cannot resolve or reach prometheus:9090"
fi

if docker compose exec -T grafana sh -c 'wget -qO- http://loki:3100/ready >/dev/null'; then
  ok "Grafana can resolve and reach loki:3100"
else
  fail "Grafana cannot resolve or reach loki:3100"
fi

if (( failures > 0 )); then
  printf '\nVerification failed with %d issue(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAll observability services passed verification.\n'
