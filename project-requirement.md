# Codex Task — Build the Central Observability Server

## Objective

Build a production-oriented but intentionally simple **central observability project** that I can deploy on a VPS with:

```bash
git clone <repository-url> observability
cd observability

cp .env.example .env
# configure .env

docker compose config
docker compose up -d
```

After the initial clone, normal updates should be:

```bash
git pull
docker compose config
docker compose up -d
```

The project must run the central observability services under one Docker Compose project named `observability`.

The initial stack is intentionally limited to:

- **Grafana** — dashboards, Explore, and Grafana-managed alerting.
- **Prometheus** — centralized metrics backend.
- **Loki** — centralized logs backend.

Do **not** add Mimir, Tempo, Pyroscope, MinIO, S3, Thanos, a standalone Alertmanager, Node Exporter, cAdvisor, database exporters, or application agents to this central repository at this stage.

Host/application instrumentation will be added later as a separate project based primarily on Grafana Alloy.

---

# 1. Critical Requirement: Preserve the Existing Grafana Instance

There is already a Grafana Docker container/Compose deployment running on the VPS.

It already contains important data such as:

- users;
- organizations;
- dashboards;
- data sources;
- alerting configuration;
- plugins;
- other Grafana state.

**Losing or replacing this Grafana data is unacceptable.**

Grafana stores its persistent application data under:

```text
/var/lib/grafana
```

The existing Grafana Compose configuration and its existing persistent volume or bind mount must be reused.

## Mandatory migration behavior

Before modifying Grafana configuration:

1. Locate the existing Grafana Compose file.
2. Inspect the existing `grafana` service.
3. Record the exact:
   - image and image tag;
   - container/service configuration;
   - environment variables;
   - published ports;
   - networks;
   - plugins;
   - user configuration;
   - mount mapped to `/var/lib/grafana`.
4. Determine whether `/var/lib/grafana` currently uses:
   - a Docker named volume; or
   - a host bind mount.
5. Reuse the **same exact persistent data** in the new observability Compose project.

Do not assume the existing volume name.

Useful inspection commands may include:

```bash
docker inspect grafana
docker volume ls
docker volume inspect <volume>
docker compose config
```

Adapt them to the actual existing container/service name.

## If the existing Grafana data uses a named Docker volume

Prefer declaring the existing volume as an external volume in the new project, using its exact Docker volume name.

Example only:

```yaml
services:
  grafana:
    volumes:
      - grafana_data:/var/lib/grafana

volumes:
  grafana_data:
    external: true
    name: ${GRAFANA_DATA_VOLUME}
```

`GRAFANA_DATA_VOLUME` must resolve to the actual existing volume.

Do not create a new empty volume under a new Compose project name.

## If the existing Grafana data uses a bind mount

Reuse that exact host path.

Example only:

```yaml
services:
  grafana:
    volumes:
      - ${GRAFANA_DATA_PATH}:/var/lib/grafana
```

Do not copy the data to another path unless there is an explicit, verified migration procedure.

## Absolutely forbidden

Never execute or recommend any destructive command such as:

```bash
docker compose down -v
docker volume rm ...
docker system prune --volumes
```

Do not automatically:

- upgrade Grafana;
- change the Grafana image family;
- change the Grafana database;
- change the `/var/lib/grafana` mount;
- recreate Grafana with an empty volume;
- reset Grafana admin credentials;
- delete existing organizations or dashboards.

The existing Grafana image/version must be preserved initially.

Upgrading Grafana is a separate future task.

## Fail-safe rule

If the existing Grafana Compose file or `/var/lib/grafana` mount cannot be determined with certainty, **do not guess**.

Stop the Grafana migration portion and clearly report what exact information is missing.

Prometheus/Loki project work may continue independently, but the new stack must not start a replacement Grafana instance against an unknown or empty volume.

---

# 2. Desired Repository Structure

Create a clean repository similar to:

```text
observability/
├── compose.yml
├── .env.example
├── .gitignore
├── README.md
│
├── prometheus/
│   ├── prometheus.yml
│   └── targets/
│       ├── applications.yml
│       └── hosts.yml
│
├── loki/
│   └── loki.yml
│
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── observability.example.yml
│
├── nginx/
│   ├── grafana.conf.example
│   └── loki.conf.example
│
└── scripts/
    ├── preflight.sh
    └── verify.sh
```

The exact filenames may change if there is a good reason, but keep the repository small and understandable.

---

# 3. Docker Compose Requirements

Use modern Docker Compose syntax.

Prefer:

```yaml
name: observability
```

or an equivalent `COMPOSE_PROJECT_NAME=observability` approach.

The deployment command must remain:

```bash
docker compose up -d
```

Do not require Helm, Kubernetes, Ansible, Terraform, Swarm, or Make for normal operation.

## Services

The main Compose file must contain:

```text
grafana
prometheus
loki
```

No unnecessary services.

## Common rules

Every service should:

- use a pinned stable image version;
- use `restart: unless-stopped`;
- join a private Docker network named `observability`;
- have a predictable service name;
- mount its configuration read-only where practical;
- persist required runtime data;
- avoid exposing internal services publicly unless required.

Do not use `latest`.

Prometheus and Loki versions should be configurable from `.env`.

Grafana's version/image must initially match the existing deployment exactly.

---

# 4. Networking Model

There is already NGINX installed directly on the VPS.

NGINX is **outside this Compose project**.

Do not run another NGINX container.

Use this architecture:

```text
Internet
   |
   v
Existing VPS NGINX
   |
   +------> 127.0.0.1:<GRAFANA_PORT>
   |
   +------> 127.0.0.1:<LOKI_PORT>   # only when remote log ingestion is enabled

Docker observability network
   |
   +-- grafana
   +-- prometheus
   +-- loki
```

## Grafana

Grafana should be reachable by host NGINX through loopback only, for example:

```text
127.0.0.1:3000
```

Do not publish Grafana as:

```text
0.0.0.0:3000
```

unless the existing deployment already intentionally does this and changing it would break the current setup.

The preferred eventual state is loopback + NGINX HTTPS.

## Prometheus

Prometheus should normally **not be publicly exposed**.

Grafana should query it using the Docker network:

```text
http://prometheus:9090
```

Do not publish Prometheus port `9090` publicly.

If a host mapping is useful for administration/debugging, bind only to loopback:

```text
127.0.0.1:9090
```

and make it configurable.

## Loki

Grafana should query Loki internally using:

```text
http://loki:3100
```

Future Alloy agents on remote application VPSs will need to push logs to the central Loki instance.

Therefore prepare an optional loopback binding such as:

```text
127.0.0.1:3100
```

so the existing host NGINX can expose a secure HTTPS endpoint later.

Do not expose `3100` directly to the public Internet.

---

# 5. `.env` Design

Create:

```text
.env.example
```

and ensure:

```text
.env
```

is ignored by Git.

Keep configuration understandable.

Possible variables include:

```dotenv
COMPOSE_PROJECT_NAME=observability
TZ=Africa/Algiers

# Existing Grafana deployment
GRAFANA_PORT=3000
GRAFANA_BIND_ADDRESS=127.0.0.1
GRAFANA_DOMAIN=grafana.example.com
GRAFANA_ROOT_URL=https://grafana.example.com

# IMPORTANT:
# Codex must adapt this section to the actual existing Grafana mount.
GRAFANA_DATA_VOLUME=<existing-docker-volume-name>

# Do not arbitrarily change the current Grafana image/version.
GRAFANA_IMAGE=<existing-grafana-image-with-tag>

# Prometheus
PROMETHEUS_IMAGE=prom/prometheus:<pinned-version>
PROMETHEUS_BIND_ADDRESS=127.0.0.1
PROMETHEUS_PORT=9090

# Loki
LOKI_IMAGE=grafana/loki:<pinned-version>
LOKI_BIND_ADDRESS=127.0.0.1
LOKI_PORT=3100
```

These are examples.

Use names that are consistent and documented.

Avoid unnecessary environment variables.

Do not put secrets in `.env.example`.

---

# 6. Grafana Requirements

The existing Grafana deployment is authoritative.

The initial task is **integration**, not replacement.

Preserve:

```text
existing Grafana
+
existing Grafana persistent data
+
existing users
+
existing organizations
+
existing dashboards
```

while adding:

```text
Prometheus
Loki
```

next to it.

## Data sources

Prepare an example provisioning file for:

### Prometheus

```text
name: Prometheus
type: prometheus
URL: http://prometheus:9090
```

### Loki

```text
name: Loki
type: loki
URL: http://loki:3100
```

However:

**do not mount or activate new Grafana provisioning automatically if it could overwrite/conflict with existing data sources.**

Prefer one of these safe approaches:

1. provide the provisioning configuration as an example and document manual activation; or
2. provide an idempotent provisioning script that first checks existing data sources and only creates missing ones.

Do not delete or replace existing data sources.

Do not automatically create/delete Grafana organizations in this first central-stack phase.

## Alerting

Use **Grafana-managed alerting**.

Do not deploy a standalone Alertmanager for now.

---

# 7. Prometheus Requirements

Run a single Prometheus instance.

Use a repository-owned configuration file:

```text
prometheus/prometheus.yml
```

Mount it read-only into the container.

Prometheus must at minimum scrape itself:

```text
prometheus:9090
```

Where practical, also prepare scraping of the central services' own Prometheus-compatible metrics endpoints.

## Future application/host discovery

Do not hardcode every future application into `prometheus.yml`.

Prepare `file_sd_configs` so future targets can be added under:

```text
prometheus/targets/
```

For example:

```text
prometheus/targets/applications.yml
prometheus/targets/hosts.yml
```

Start these files with valid empty configurations if no targets exist yet.

The intended future workflow should be:

```text
edit a small target file
+
reload/restart Prometheus
```

rather than rewriting the full Prometheus configuration.

Example future labels should follow a consistent model:

```text
app
service
environment
instance
```

Example:

```yaml
- targets:
    - 10.10.0.20:8000
  labels:
    app: drovenai
    service: backend
    environment: production
```

This is identification/filtering only.

For this initial personal deployment, no strict Prometheus multi-tenancy is required.

---

# 8. Loki Requirements

Use a simple **single-binary / monolithic Loki** deployment suitable for one developer and a modest number of applications.

Do not introduce distributed Loki services.

Do not introduce MinIO/S3/object-storage services.

Use a normal Docker persistent volume for Loki runtime data.

For this simple single-user architecture:

```yaml
auth_enabled: false
```

is acceptable **only because Loki itself will not be exposed directly to the public Internet**.

The future public ingestion path should be:

```text
Remote Alloy
    |
 HTTPS
    v
Host NGINX
    |
    v
127.0.0.1:3100
    |
    v
Loki
```

Document that remote ingestion must be protected at the NGINX/network layer before exposing it.

Loki should expose readiness internally at:

```text
/ready
```

Grafana should use the Docker-internal endpoint:

```text
http://loki:3100
```

---

# 9. NGINX Examples

The existing VPS NGINX installation must not be modified automatically.

Instead, create example snippets under:

```text
nginx/
```

## `grafana.conf.example`

Show a secure HTTPS reverse-proxy example conceptually like:

```text
grafana.example.com
    ->
127.0.0.1:${GRAFANA_PORT}
```

Include the important reverse-proxy headers needed for Grafana.

Do not include real certificates, domains, credentials, or private keys.

## `loki.conf.example`

Prepare a future Loki ingestion reverse-proxy example.

It must clearly warn that Loki's ingestion endpoint must not simply be exposed anonymously to the Internet.

Show placeholders for one or more protection mechanisms such as:

- private VPN/network;
- IP allow-list;
- NGINX Basic Auth;
- another explicit authentication layer.

Do not invent production credentials.

---

# 10. Persistence

Use persistent Docker volumes for new central services where required.

At minimum:

```text
Prometheus runtime data
Loki runtime data
```

must survive normal container recreation.

Grafana must continue using its **existing** persistence mechanism.

Do not add external storage platforms.

Do not add backup platforms.

The only migration-sensitive persistence in this task is the existing Grafana data.

---

# 11. Security Baseline

Apply these defaults:

- only Grafana and the future Loki ingestion endpoint may need host-loopback ports;
- no service should bind internal admin ports directly to public interfaces;
- Prometheus should remain private;
- use the existing host NGINX for HTTPS;
- configuration files should not contain credentials;
- `.env` must be Git-ignored;
- `.env.example` must contain placeholders only;
- no anonymous Grafana access should be enabled unless it already exists intentionally;
- do not reset Grafana security configuration;
- do not expose Loki publicly without an authentication/network control layer.

---

# 12. Image Versioning

Do not use:

```text
latest
```

for any production service.

Pin explicit versions.

Before choosing Prometheus or Loki versions:

1. check the current stable releases from their official projects;
2. choose stable non-preview releases;
3. store the image tags in `.env.example`;
4. document upgrade steps in `README.md`.

For Grafana:

**preserve the existing image and exact version for this migration.**

Do not upgrade Grafana as part of this task.

---

# 13. Preflight Script

Create:

```text
scripts/preflight.sh
```

It should be non-destructive.

It should validate as much as possible, including:

```text
Docker installed
Docker Compose available
.env exists
docker compose config succeeds
required configuration files exist
Grafana persistence value is configured
external Grafana volume exists if using a named external volume
required ports are not unexpectedly occupied
```

For the Grafana volume check:

```bash
docker volume inspect "$GRAFANA_DATA_VOLUME"
```

should fail the preflight if the expected external volume does not exist.

**Do not automatically create a missing Grafana volume.**

That behavior protects against accidentally starting a fresh Grafana instance.

---

# 14. Verification Script

Create:

```text
scripts/verify.sh
```

It should perform safe checks after:

```bash
docker compose up -d
```

Check:

```text
Grafana container running
Prometheus container running
Loki container running
Grafana health endpoint responds
Prometheus health endpoint responds
Loki /ready responds
Grafana can resolve prometheus over the Docker network
Grafana can resolve loki over the Docker network
```

Print a simple success/failure summary.

Do not mutate data.

---

# 15. README Requirements

Create a concise but complete `README.md`.

It must include:

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

## Initial deployment

```bash
git clone <repo>
cd observability

cp .env.example .env
nano .env

./scripts/preflight.sh
docker compose config
docker compose up -d
./scripts/verify.sh
```

## Normal deployment/update

```bash
git pull
docker compose config
docker compose up -d
./scripts/verify.sh
```

## Safe Grafana migration

Document the exact migration from the old Grafana Compose deployment into this project.

The documentation must explain:

1. how the existing volume/bind mount was identified;
2. what exact old resource is reused;
3. how to stop only the old Grafana container safely;
4. how to start the new Compose service with the same persistent data;
5. how to verify that old users, organizations, and dashboards still exist;
6. how to roll back to the old Compose file if verification fails.

Never tell the user to run `down -v`.

## Useful commands

Include:

```bash
docker compose ps
docker compose logs -f grafana
docker compose logs -f prometheus
docker compose logs -f loki

docker compose restart prometheus
docker compose restart loki
```

## Adding future Prometheus targets

Explain how to add:

```text
application metrics
host metrics
database metrics
Docker metrics
```

later through target files without changing the central architecture.

Do not implement the future host-agent project yet.

---

# 16. Git Ignore

At minimum ignore:

```gitignore
.env
*.local
.DS_Store
```

Do not ignore repository-owned Prometheus/Loki configuration.

Do not commit:

- passwords;
- authentication files containing real hashes unless explicitly intended;
- TLS private keys;
- Grafana database exports;
- production `.env`.

---

# 17. Scope Boundaries

For this task, do **not** implement:

- Grafana Alloy host agents;
- Beyla;
- Laravel instrumentation;
- Node instrumentation;
- OpenTelemetry SDK configuration;
- Tempo/tracing;
- Mimir;
- Pyroscope;
- MinIO/S3;
- Thanos;
- Kubernetes;
- Terraform;
- database exporters;
- cAdvisor;
- Node Exporter;
- a custom observability API.

Those belong to later phases.

The goal right now is a reliable, simple **central observability server**.

---

# 18. Expected Final State

After implementation, this should work:

```bash
git pull
docker compose up -d
```

and result in:

```text
observability
│
├── grafana
│    └── existing data preserved
│
├── prometheus
│    └── central metrics
│
└── loki
     └── central logs
```

The Docker network should conceptually be:

```text
observability
├── grafana
├── prometheus
└── loki
```

Grafana queries:

```text
http://prometheus:9090
http://loki:3100
```

Existing NGINX proxies:

```text
https://grafana.example.com
    ->
127.0.0.1:<grafana-port>
```

Later, remote host agents will feed metrics/logs into this central system without redesigning the Grafana/Prometheus/Loki stack.

---

# 19. Definition of Done

The task is complete only when all of the following are true:

- [ ] Existing Grafana persistent data location was identified.
- [ ] New Compose reuses that exact existing Grafana data.
- [ ] Existing Grafana image/version was preserved.
- [ ] Existing Grafana users remain available.
- [ ] Existing Grafana organizations remain available.
- [ ] Existing dashboards remain available.
- [ ] `docker compose config` succeeds.
- [ ] `docker compose up -d` starts the required services.
- [ ] Grafana is reachable through its expected local port.
- [ ] Prometheus is running.
- [ ] Loki is running and `/ready` reports ready.
- [ ] Prometheus is not publicly exposed.
- [ ] Loki is not directly publicly exposed.
- [ ] Grafana can reach Prometheus by Docker service name.
- [ ] Grafana can reach Loki by Docker service name.
- [ ] `.env` is not committed.
- [ ] Images are pinned; no `latest`.
- [ ] `scripts/preflight.sh` is non-destructive.
- [ ] `scripts/verify.sh` passes.
- [ ] README documents safe deployment and rollback.
- [ ] No unnecessary observability services were added.

---

# 20. Implementation Principles

Prefer:

```text
simple
explicit
idempotent
easy to inspect
safe to update
safe for existing Grafana data
```

over clever automation.

Do not introduce complexity unless the requirement genuinely needs it.

The most important requirement is:

> **Integrate the existing Grafana deployment without losing or replacing its persistent data.**

---

# Official References

Use official documentation as the primary source during implementation:

- Grafana Docker installation and persistent data:
  https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/

- Grafana Docker configuration:
  https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/

- Prometheus Docker installation:
  https://prometheus.io/docs/prometheus/latest/installation/

- Loki Docker installation:
  https://grafana.com/docs/loki/latest/setup/install/docker/

- Loki fundamentals / single-binary configuration:
  https://grafana.com/docs/loki/latest/get-started/quick-start/tutorial/

If implementation details conflict with old examples, prefer current official documentation and stable releases.
