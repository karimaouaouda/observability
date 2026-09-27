# Central observability server

A small, single-host Grafana, Prometheus, and Loki deployment managed as the
Docker Compose project `observability`. Grafana-managed alerting remains in the
existing Grafana instance; no standalone Alertmanager is deployed.

## Architecture

```text
                     +--------------------+
                     |      Grafana       |
                     | dashboards/alerts  |
                     +----------+---------+
                                |
                       +--------+--------+
                       |                 |
                       v                 v
                 Prometheus            Loki
                   metrics              logs
```

Host NGINX sends Grafana traffic to port `3011`. Prometheus and Loki are bound
to loopback by default. Inside Docker, Grafana reaches the backends at
`http://prometheus:9090` and `http://loki:3100`.

## Preserved Grafana deployment

The source deployment at `services/grafana/docker-compose.yaml` was inspected.
Its migration-sensitive settings are:

| Setting | Preserved value |
| --- | --- |
| Image | `grafana/grafana:13.2.2` |
| Container | `grafana` |
| Published port | `3011:3000` |
| Network | `observability` |
| Data mount | Docker volume `grafana_data` at `/var/lib/grafana` |
| Provisioning | Not enabled |

No explicit container user or plugin-install variable was configured. Existing
plugins remain in the data volume. The preserved environment configuration is
`GF_SERVER_DOMAIN`, `GF_SERVER_ROOT_URL`, `GF_SERVER_ENFORCE_DOMAIN`, the two
existing admin bootstrap variables, secure/lax cookie settings, disabled
Gravatar, sign-up and anonymous access, disabled analytics reporting, enabled
update checks, and console/info logging. The original JSON log rotation,
health-check, restart policy, and `no-new-privileges` setting are also preserved.
The Compose volume is declared
`external: true` with exact name `grafana_data`; Docker Compose therefore fails
instead of creating an empty replacement if the volume is absent.

The old port binding listens on all host interfaces. It is preserved for the
initial migration to avoid breaking the existing NGINX route. After verifying
NGINX, set `GRAFANA_BIND_ADDRESS=127.0.0.1` and redeploy to restrict it.
The existing `observability` Docker network is also reused as an external
network so Compose does not collide with the network owned by the old project.

## Initial deployment and safe Grafana migration

Perform this on the VPS where the existing Grafana container and volume live.
Never use `docker compose down -v`, remove `grafana_data`, or run a volume prune.

1. Clone and configure the project. Copy the three existing Grafana values
   (`GRAFANA_DOMAIN`, `GRAFANA_ADMIN_USER`, and `GRAFANA_ADMIN_PASSWORD`) from
   the old deployment's `.env`; do not choose new credentials during migration.

   ```bash
   git clone <repository-url> observability
   cd observability
   cp .env.example .env
   nano .env
   ```

2. Independently confirm the live container matches the recorded image and
   named volume. The preflight repeats these checks and never creates a missing
   Grafana volume.

   ```bash
   docker inspect grafana --format '{{.Config.Image}}'
   docker inspect grafana --format '{{range .Mounts}}{{println .Name .Source "->" .Destination}}{{end}}'
   docker volume inspect grafana_data
   docker network inspect observability
   ./scripts/preflight.sh
   docker compose config
   ```

   Stop if `/var/lib/grafana` does not map to `grafana_data`, or if the live
   image is not `grafana/grafana:13.2.2`. Correct `.env` and `compose.yml` from
   the live values before continuing; never guess.

3. Stop only the old Grafana container and retain it for rollback. Renaming it
   releases the fixed container name without deleting its data or configuration.

   ```bash
   cd /path/to/old/grafana/compose
   docker compose stop grafana
   docker rename grafana grafana-pre-observability
   cd /path/to/observability
   docker compose up -d
   ./scripts/verify.sh
   ```

4. Sign in through the existing Grafana URL. Verify several existing users,
   organizations, dashboards, data sources, alert rules, and installed plugins.
   The example datasource file is deliberately not mounted; add Prometheus and
   Loki manually in Grafana only if data sources with those URLs do not exist.

5. If verification fails, roll back without touching the volume:

   ```bash
   cd /path/to/observability
   docker compose stop grafana
   docker compose rm -f grafana
   docker rename grafana-pre-observability grafana
   docker start grafana
   ```

   Prometheus and Loki can remain running. Once the migration has been fully
   accepted, the stopped backup container may be removed; the `grafana_data`
   volume must remain.

## Normal deployment and updates

```bash
git pull
./scripts/preflight.sh
docker compose config
docker compose up -d
./scripts/verify.sh
```

Useful operational commands:

```bash
docker compose ps
docker compose logs -f grafana
docker compose logs -f prometheus
docker compose logs -f loki

docker compose restart prometheus
docker compose restart loki
```

## Data sources

`grafana/provisioning/datasources/observability.example.yml` documents the two
data sources, but is intentionally not activated because file provisioning
could conflict with existing Grafana-managed data sources. In the Grafana UI,
create only missing entries:

- Prometheus: `http://prometheus:9090`
- Loki: `http://loki:3100`

## Adding Prometheus targets

Add application endpoints to `prometheus/targets/applications.yml` and host,
database, or Docker exporter endpoints to `prometheus/targets/hosts.yml`. Keep
the label model consistent; for example:

```yaml
- targets:
    - 10.10.0.20:8000
  labels:
    app: drovenai
    service: backend
    environment: production
    instance: app-vps-1
```

Prometheus watches these files every 30 seconds. Validate changes before relying
on them:

```bash
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

This repository does not install exporters or agents; those belong in the
future host/application instrumentation project.

## Loki ingestion and NGINX

Loki runs in single-binary mode with authentication disabled, filesystem TSDB
storage, schema v13, and persistent volume `observability_loki_data`. Its host
port is loopback-only. Do not make port 3100 public. Before accepting remote
logs, expose it through HTTPS using a private VPN/network, an IP allow-list,
NGINX Basic Auth, or another explicit authentication layer. Example NGINX
snippets are under `nginx/` and are never installed automatically.

## Persistence and upgrades

- Grafana: external, pre-existing `grafana_data` volume.
- Prometheus: `observability_prometheus_data` volume.
- Loki: `observability_loki_data` volume.

For an upgrade, read the upstream release notes and migration guidance, change
one image tag in `.env`, run `docker compose config`, deploy, and verify. Back up
service data first. Grafana upgrades are a separate task: do not change its tag
during this migration. Loki schema changes require a new future-dated schema
period; never rewrite a schema period that already contains data.

## Upstream references

- [Grafana Docker installation and persistence](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Prometheus downloads](https://prometheus.io/download/)
- [Loki Docker installation](https://grafana.com/docs/loki/latest/setup/install/docker/)
- [Loki filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/)
- [Loki storage schemas](https://grafana.com/docs/loki/latest/operations/storage/schema/)
