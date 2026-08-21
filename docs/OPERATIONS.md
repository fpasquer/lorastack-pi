# IoT Infrastructure — Operations

This document describes how the Raspberry Pi Docker stack is built, how to
operate it, and how to diagnose problems. No credentials are stored here —
all secrets live in `.env` (never committed); see `.env.example`.

---

## 1. Architecture

```text
                 LAN (192.168.1.0/24)
                    │
   ┌────────────────┼──────────────────────────┐
   │    1883/tcp    │  8080/tcp   1700/udp     │   published ports
   │                │                          │
   │  Mosquitto ────┼── ChirpStack ── Gateway-Bridge
   │     │          │      │             │     │   network: iot-lan
   ╞═════╪══════════╪══════╪═════════════╪═════╡
   │     │          │      │             │     │   network: iot-internal
   │     └──────────┴──┬───┴─────────────┘     │   (no internet egress,
   │                   │                       │    no published ports)
   │              PostgreSQL   Redis           │
   └───────────────────────────────────────────┘
```

| Service | Image | Role |
|---|---|---|
| chirpstack | chirpstack/chirpstack:4 | LoRaWAN network server (v4, EU868) |
| chirpstack-gateway-bridge | chirpstack/chirpstack-gateway-bridge:4 | Semtech UDP (1700) ↔ MQTT bridge for the LPS8N |
| postgres | postgres:16-alpine | ChirpStack database (v13+ required, `pg_trgm`) |
| redis | redis:7-alpine | ChirpStack cache/queues/metrics (>= 6.2 required) |
| mosquitto | eclipse-mosquitto:2 | MQTT broker (MQTT v5 + shared subscriptions) |

Why the gateway bridge exists: ChirpStack v4 communicates with gateways over
MQTT only. The Dragino LPS8N uses the Semtech UDP packet-forwarder protocol,
so `chirpstack-gateway-bridge` terminates UDP 1700 and bridges it to MQTT
with the `eu868` topic prefix. This follows the current official
chirpstack-docker architecture.

## 2. Networks

| Network | Type | Members | Purpose |
|---|---|---|---|
| iot-internal | bridge, `internal: true` | all 5 services | service-to-service traffic; no internet egress; **PostgreSQL and Redis exist only here** |
| iot-lan | bridge | mosquitto, chirpstack, gateway-bridge | carries the published ports |

Note: Docker cannot publish ports on an `internal` network — that is why the
LAN-facing services are attached to both networks.

## 3. Published ports (complete list)

| Port | Service | Why it is published |
|---|---|---|
| 1883/tcp | mosquitto | The laptop (Symfony) consumes MQTT over the LAN. Anonymous access is rejected. |
| 8080/tcp | chirpstack | Web UI + gRPC API administration from the LAN. |
| 1700/udp | chirpstack-gateway-bridge | Semtech UDP packet forwarder endpoint for the LPS8N. |

NOT published (internal only): PostgreSQL 5432, Redis 6379, ChirpStack
monitoring 8081 (healthcheck only).

### Restricting UDP 1700 to the LPS8N (Phase 6 task)

Once the LPS8N has a reserved DHCP address (e.g. `192.168.1.50`), restrict
1700/udp with a `DOCKER-USER` iptables rule (Docker bypasses ufw):

```bash
sudo iptables -I DOCKER-USER -p udp --dport 1700 ! -s 192.168.1.50 -j DROP
# persist with: sudo apt install iptables-persistent
```

## 4. Volumes and persistence

| Volume / path | Content |
|---|---|
| `postgresqldata` (named volume) | ChirpStack database — **the critical state** |
| `redisdata` (named volume) | Redis snapshots (cache; safe to lose, kept for warm restarts) |
| `mosquittodata` (named volume) | MQTT retained messages / subscriptions |
| `mosquittolog` (named volume) | mosquitto.log |
| `./configuration/` (bind mounts, read-only in containers) | all service configuration; version controlled |

Survives container recreation, Docker restart and Pi reboot
(`restart: unless-stopped` on all services). Verified with a full
`docker compose down && docker compose up -d` cycle.

## 5. Environment variables

All secrets are in `.env` (mode 600, git-ignored). See `.env.example` for the
complete list and generation instructions:

| Variable | Used by |
|---|---|
| `POSTGRES_PASSWORD` | postgres, chirpstack (DSN) |
| `MQTT_CHIRPSTACK_USERNAME/PASSWORD` | chirpstack (integration + eu868 gateway backend), mosquitto healthcheck |
| `MQTT_GWBRIDGE_USERNAME/PASSWORD` | chirpstack-gateway-bridge |
| `MQTT_SYMFONY_USERNAME/PASSWORD` | reserved for the laptop (Phase 8/9); subscribe-only per ACL |
| `CHIRPSTACK_API_SECRET` | chirpstack API token signing |

MQTT authorization is enforced by `configuration/mosquitto/config/acl`:
- `chirpstack`: read/write `eu868/gateway/#`, `application/#`
- `gatewaybridge`: read/write `eu868/gateway/#`
- `symfony`: **read-only** `application/#` (verified: its publishes are dropped)

## 6. Daily operations

```bash
cd /opt/iot

docker compose up -d        # start / apply changes
docker compose down         # stop everything (data persists in volumes)
docker compose restart      # restart all services
docker compose ps           # status incl. health
docker compose logs -f chirpstack
docker compose logs -f mosquitto
docker compose logs -f chirpstack-gateway-bridge
```

Update images (major tags are pinned: `:4`, `:2`, `:16-alpine`, `:7-alpine`):

```bash
docker compose pull && docker compose up -d
```

Docker log rotation is configured per service: json-file, `max-size: 10m`,
`max-file: 3` (max ~30 MB of logs per service).

## 7. Health checks

| Service | Check |
|---|---|
| postgres | `pg_isready -U chirpstack` |
| redis | `redis-cli ping` |
| mosquitto | authenticated `mosquitto_sub` on `$SYS/broker/uptime` (validates listener + password file + ACL) |
| chirpstack | HTTP GET on internal monitoring endpoint `:8081/health` |
| gateway-bridge | none (no health endpoint); verify via `logs` — look for `connected to mqtt broker` |

## 8. Troubleshooting

| Symptom | Where to look |
|---|---|
| ChirpStack unhealthy | `docker compose logs chirpstack` — check DSN/Redis/MQTT lines at startup |
| UI not reachable | `docker compose ps` — port `0.0.0.0:8080->8080` must be listed |
| MQTT auth fails | `docker compose logs mosquitto`; passwords must match `.env` and `configuration/mosquitto/config/passwd` (regenerate with `mosquitto_passwd`) |
| ACL question | publish test messages and watch for delivery; broker drops unauthorized QoS 0 publishes silently |
| Gateway offline (Phase 6+) | `docker compose logs chirpstack-gateway-bridge`; LPS8N `LogRead` page; confirm LPS8N points to Pi IP port 1700 and that "Internet Detect" is disabled on the LPS8N |
| Disk pressure | `df -h`, `docker system df` |

### Regenerating the Mosquitto password file

```bash
cd /opt/iot && set -a && . ./.env && set +a
docker run --rm -v /opt/iot/configuration/mosquitto/config:/cfg \
  eclipse-mosquitto:2 sh -c "rm -f /cfg/passwd && touch /cfg/passwd && \
  mosquitto_passwd -b /cfg/passwd \"$MQTT_CHIRPSTACK_USERNAME\" \"$MQTT_CHIRPSTACK_PASSWORD\" && \
  mosquitto_passwd -b /cfg/passwd \"$MQTT_GWBRIDGE_USERNAME\" \"$MQTT_GWBRIDGE_PASSWORD\" && \
  mosquitto_passwd -b /cfg/passwd \"$MQTT_SYMFONY_USERNAME\" \"$MQTT_SYMFONY_PASSWORD\" && \
  chown 1883:1883 /cfg/passwd && chmod 0600 /cfg/passwd"
docker compose restart mosquitto
```

## 9. Backup and recovery

```bash
# 1. Stop the stack
docker compose down

# 2. Back up volumes + configuration
cd /opt/iot
tar czf iot-backup-$(date +%F).tar.gz configuration .env.example
for v in postgresqldata redisdata mosquittodata mosquittolog; do
  docker run --rm -v iot_$v:/data -v $PWD:/backup alpine \
    tar czf /backup/$v-$(date +%F).tar.gz -C /data .
done
# (also store a copy of .env somewhere safe — it is NOT in git)

# 3. Restore: recreate volumes, extract archives into them, restore
#    configuration/ and .env, then `docker compose up -d`.
```

## 10. Security summary

- No default passwords anywhere; all secrets random, in `.env` (mode 600).
- Mosquitto rejects anonymous connections (verified) and enforces per-user ACLs.
- PostgreSQL and Redis have no published ports and sit on an internal-only
  network (verified unreachable from the LAN).
- The Docker socket is never mounted into any container.
- No container runs with extra privileges or capabilities.
- Remaining follow-ups (documented, not Phase 1–5 scope):
  - Change ChirpStack web UI `admin/admin` password on first login.
  - Add the DOCKER-USER firewall rule for 1700/udp once the LPS8N IP is fixed.
  - Consider TLS on a second Mosquitto listener (8883) if the LAN is not
    fully trusted.
  - Change LPS8N default credentials and disable its "Internet Detect"
    feature (otherwise it reboots every 15 minutes without internet).

## 11. Resource baseline (Pi 4, 2 GB)

No aggressive tuning applied on purpose. PostgreSQL/Redis run with stock
settings plus Redis snapshot persistence (`--save 300 1 --save 60 100`).
Measure before optimizing:

```bash
free -h
docker stats --no-stream
df -h
```
