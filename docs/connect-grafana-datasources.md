# Connect Grafana to Prometheus and Loki

This guide connects the existing Grafana instance to the Prometheus and Loki
services in this Docker Compose project.

## Before you begin

Start and verify the stack:

```bash
docker compose up -d
./scripts/verify.sh
```

You need the **Organization administrator** role in Grafana to manage data
sources. Before adding anything, open **Connections > Data sources** and check
whether equivalent Prometheus or Loki data sources already exist. Do not delete
or replace an existing data source used by dashboards or alerts.

Use these Docker-internal URLs:

| Data source | URL |
| --- | --- |
| Prometheus | `http://prometheus:9090` |
| Loki | `http://loki:3100` |

Do not use `localhost` in Grafana's data source settings. Grafana runs in its
own container, so `localhost` would refer to the Grafana container itself.

## Add Prometheus

1. Sign in to Grafana.
2. Select **Connections > Add new connection**.
3. Search for and select **Prometheus**.
4. Select **Add new data source**.
5. Set **Name** to `Prometheus`.
6. Set **Prometheus server URL** to:

   ```text
   http://prometheus:9090
   ```

7. Select **No authentication**. Prometheus is protected by the private Docker
   network and is not exposed publicly.
8. Leave the remaining settings at their defaults initially.
9. Select **Save & test**.

The expected result is a message stating that Grafana successfully queried the
Prometheus API.

To test queries, open **Explore**, select `Prometheus`, and run:

```promql
up
```

At minimum, the `prometheus`, `grafana`, and `loki` scrape jobs should appear.
You can inspect their status directly under **Status > Targets** in Prometheus,
using the loopback address from the VPS:

```text
http://127.0.0.1:9090/targets
```

## Add Loki

1. Select **Connections > Add new connection**.
2. Search for and select **Loki**.
3. Select **Add new data source**.
4. Set **Name** to `Loki`.
5. Set **URL** to:

   ```text
   http://loki:3100
   ```

6. Do not append `/loki/api/v1/push`; that is an ingestion endpoint, not the
   data source query URL.
7. Select **No authentication**. This Loki deployment has `auth_enabled: false`
   and is reachable only through the private Docker network and host loopback.
8. Leave the remaining settings at their defaults initially.
9. Select **Save & test**.

To test queries, open **Explore**, select `Loki`, and use the label browser. Once
an agent has sent logs, a general example query is:

```logql
{job=~".+"}
```

A successful connection can still return no log streams when no Grafana Alloy
or other log agent has pushed logs yet. Log collection agents are intentionally
outside this central-server project.

## Verify connectivity from the Grafana container

If **Save & test** fails, run:

```bash
docker compose ps

docker compose exec -T grafana \
  wget -qO- http://prometheus:9090/-/healthy

docker compose exec -T grafana \
  wget -qO- http://loki:3100/ready
```

Both endpoint checks should return a successful response. Also review logs:

```bash
docker compose logs --tail=100 grafana
docker compose logs --tail=100 prometheus
docker compose logs --tail=100 loki
```

Common causes of connection failure are:

- using `localhost` instead of the Docker service name;
- entering an ingestion API path instead of Loki's base URL;
- one of the services not running;
- Grafana not being attached to the `observability` network;
- a duplicate or previously provisioned data source with conflicting settings.

Check network membership with:

```bash
docker network inspect observability
```

## Optional file provisioning

An example exists at
`grafana/provisioning/datasources/observability.example.yml`, but it is not
mounted into Grafana. This is intentional: automatically enabling provisioning
could conflict with existing data sources, dashboards, or alert rules. For this
migration, use the Grafana UI and create only missing data sources.

## Official documentation

- [Configure the Prometheus data source](https://grafana.com/docs/grafana/latest/datasources/prometheus/configure/)
- [Configure the Loki data source](https://grafana.com/docs/grafana/latest/datasources/loki/configure/)

