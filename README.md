# IoT Infrastructure — Raspberry Pi

Local, self-hosted IoT infrastructure based on **LoRaWAN, ChirpStack, MQTT and Docker**.

This repository contains the infrastructure layer of the IoT project running on a dedicated Raspberry Pi.

The application/backend layer is intentionally kept separate and currently runs on a development laptop.

The project is designed to operate **locally**, without The Things Network (TTN) or an external IoT cloud platform.

---

# 1. Project Overview

The objective is to build a reliable and extensible local IoT platform capable of:

* receiving data from LoRaWAN sensors;
* processing LoRaWAN traffic through ChirpStack;
* exposing sensor data through MQTT;
* allowing application services to consume that data;
* eventually controlling physical actuators such as pumps and electrovalves;
* maintaining recoverable persistent infrastructure through automated backups.

The first phase deliberately focuses on the infrastructure required to establish a reliable data pipeline.

## Phase 1

```text
LoRaWAN sensor
      │
      ▼
LPS8N gateway
      │
      │ Semtech UDP
      ▼
ChirpStack Gateway Bridge
      │
      │ MQTT
      ▼
Mosquitto
      │
      │ MQTT
      ▼
ChirpStack
      │
      │ MQTT application integration
      ▼
Symfony
      │
      ▼
MySQL
```

The Raspberry Pi hosts the LoRaWAN infrastructure.

Symfony and MySQL are currently hosted separately on a development laptop.

---

# 2. Design Principles

The project follows these principles:

* **Local-first**
* **No mandatory cloud dependency**
* **No TTN dependency**
* **Docker-based infrastructure**
* **Persistent storage**
* **ARM64 compatibility**
* **Minimal exposed network ports**
* **Clear separation between infrastructure and application logic**
* **Automated and validated backups**
* **Documented recovery procedures**
* **Prefer official documentation and supported configurations**
* **Avoid unnecessary infrastructure complexity**

The system should remain usable even when Internet connectivity is unavailable, provided the local network and infrastructure remain operational.

Persistent IoT infrastructure must also remain recoverable after container failures, host failures and accidental data loss.

---

# 3. Current Hardware

## Raspberry Pi

The Raspberry Pi is the permanent IoT infrastructure server.

Current operating system:

```text
Debian GNU/Linux 13 (Trixie)

Architecture: ARM64 / aarch64
RAM: 2 GB
```

The Raspberry Pi is intended to operate continuously.

The limited 2 GB RAM footprint is an explicit design constraint. Additional services should therefore not be introduced without a demonstrated need.

The Raspberry Pi hosts the core IoT infrastructure and is backed up to separate physical storage.

## LoRaWAN Gateway

```text
Dragino LPS8N
```

The LPS8N receives LoRaWAN radio traffic from sensors and forwards the traffic over the local network using the Semtech UDP packet-forwarder protocol.

The gateway does not contain application logic.

## Current LoRaWAN Sensor

```text
Dragino SE01-LB
```

The SE01-LB is currently the first sensor connected to the platform.

Additional sensors and actuators will be added progressively.

---

# 4. Architecture

## 4.1 Current Architecture

```text
                         LoRaWAN
                            │
                            ▼
                    ┌──────────────┐
                    │    SE01-LB   │
                    │    Sensor    │
                    └──────┬───────┘
                           │
                           │ LoRaWAN radio
                           ▼
                    ┌──────────────┐
                    │    LPS8N     │
                    │   Gateway    │
                    └──────┬───────┘
                           │
                           │ Semtech UDP
                           │ UDP :1700
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    RASPBERRY PI                         │
│                                                         │
│                       Docker                            │
│                                                         │
│  ┌───────────────────────────────┐                      │
│  │ ChirpStack Gateway Bridge     │                      │
│  │                               │                      │
│  │ Semtech UDP → MQTT            │                      │
│  └───────────────┬───────────────┘                      │
│                  │                                      │
│                  │ MQTT                                 │
│                  ▼                                      │
│          ┌─────────────────┐                            │
│          │   Mosquitto     │                            │
│          │   MQTT Broker   │                            │
│          └────────┬────────┘                            │
│                   │                                     │
│                   │ MQTT                                │
│                   ▼                                     │
│          ┌─────────────────┐                            │
│          │   ChirpStack    │                            │
│          │ LoRaWAN Server  │                            │
│          └───────┬─────────┘                            │
│                  │                                      │
│          ┌───────┴────────┐                             │
│          ▼                ▼                             │
│   ┌─────────────┐  ┌─────────────┐                      │
│   │ PostgreSQL  │  │    Redis    │                      │
│   └─────────────┘  └─────────────┘                      │
│                                                         │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ MQTT / LAN
                       ▼
                ┌───────────────┐
                │    LAPTOP     │
                │               │
                │   Symfony     │
                │      │        │
                │      ▼        │
                │    MySQL      │
                └───────────────┘
```

This is the architecture that should be considered the **current source of truth** for Phase 1.

---

# 5. LoRaWAN Data Flow

The complete path of an uplink is:

```text
SE01-LB
   │
   │ LoRaWAN radio
   ▼
LPS8N
   │
   │ Semtech UDP
   │ UDP port 1700
   ▼
ChirpStack Gateway Bridge
   │
   │ MQTT
   ▼
Mosquitto
   │
   │ MQTT gateway topics
   ▼
ChirpStack
   │
   │ MQTT integration
   ▼
Mosquitto
   │
   │ MQTT application topics
   ▼
Symfony
   │
   ▼
MySQL
```

There are therefore **two distinct MQTT roles**:

1. MQTT is used internally by the ChirpStack Gateway Bridge and ChirpStack.
2. MQTT is also used as the application integration mechanism for Symfony.

Mosquitto is the central MQTT broker for both roles.

---

# 6. Gateway Communication

The LPS8N uses the **Semtech UDP packet-forwarder protocol**.

The Raspberry Pi runs:

```text
chirpstack-gateway-bridge
```

The Gateway Bridge receives the Semtech UDP traffic and converts it into MQTT messages.

Conceptually:

```text
LPS8N
 │
 │ Semtech UDP :1700
 ▼
Gateway Bridge
 │
 │ MQTT
 ▼
Mosquitto
 │
 ▼
ChirpStack
```

The Gateway Bridge is therefore an important component of the architecture and must not be omitted from diagrams or documentation.

ChirpStack's official architecture documentation describes the Gateway Bridge as the component that converts Semtech UDP or Basics Station traffic into MQTT.

For a Semtech UDP gateway, the gateway's packet-forwarder configuration points to the server running the Gateway Bridge, normally using UDP port `1700`.

---

# 7. Raspberry Pi Services

The Raspberry Pi currently runs the following Docker services, all defined in `docker-compose.yml`.

| Service                     | Image                                    | Purpose                             |
| --------------------------- | ---------------------------------------- | ----------------------------------- |
| `chirpstack`                | `chirpstack/chirpstack:4`                | LoRaWAN Network Server (v4, EU868)  |
| `chirpstack-gateway-bridge` | `chirpstack/chirpstack-gateway-bridge:4` | Semtech UDP → MQTT gateway bridge   |
| `mosquitto`                 | `eclipse-mosquitto:2`                    | MQTT broker                         |
| `postgres`                  | `postgres:16-alpine`                     | ChirpStack persistent database      |
| `redis`                     | `redis:7-alpine`                         | ChirpStack cache / queues / metrics |

All services use `restart: unless-stopped` and per-service Docker log rotation:

```text
json-file
max-size: 10m
max-file: 3
```

These services form the infrastructure layer.

Application services such as Symfony and MySQL are intentionally outside this repository's Raspberry Pi stack.

---

# 8. ChirpStack

ChirpStack is responsible for the LoRaWAN Network Server functionality.

Its responsibilities include:

* gateway management;
* device management;
* application management;
* LoRaWAN network management;
* uplink processing;
* downlink processing;
* LoRaWAN security;
* device sessions and network state;
* integration with MQTT and other application interfaces.

ChirpStack communicates with the gateway infrastructure through MQTT.

The Gateway Bridge is responsible for converting the gateway's packet-forwarder protocol into MQTT.

The official ChirpStack architecture documents MQTT as the communication layer between the gateway bridge and ChirpStack.

---

# 9. ChirpStack Gateway Bridge

The Gateway Bridge is responsible for connecting the LPS8N's Semtech UDP packet-forwarder protocol to the MQTT broker.

Its main responsibility is:

```text
Semtech UDP
      │
      ▼
Gateway Bridge
      │
      ▼
MQTT
```

It does not replace ChirpStack.

It does not process LoRaWAN application data.

It is a protocol bridge between the gateway and the MQTT infrastructure.

The current deployment uses the `semtech_udp` backend.

The default Semtech UDP port is:

```text
1700
```

The MQTT topic configuration must remain compatible with the ChirpStack region configuration, currently EU868.

---

# 10. Mosquitto

Mosquitto is the local MQTT broker.

It provides the messaging infrastructure between:

```text
Gateway Bridge
       │
       ▼
   Mosquitto
       │
       ├── ChirpStack
       │
       └── Application services
```

MQTT is intentionally retained as the main integration mechanism because it is lightweight, well suited to IoT systems and already supported natively by ChirpStack.

The MQTT topic structure should remain compatible with the standard ChirpStack topic structure unless there is a strong technical reason to introduce an abstraction layer.

Do not introduce another message broker without a demonstrated requirement.

---

# 11. PostgreSQL

PostgreSQL is the persistent database used by ChirpStack.

Verified configuration:

* image: `postgres:16-alpine`;
* database: `chirpstack`;
* user: `chirpstack`;
* password: injected from `POSTGRES_PASSWORD` in `.env`;
* persistent volume: `postgresqldata` mounted at `/var/lib/postgresql/data`;
* initialization: `configuration/postgresql/initdb/001-chirpstack.sql` creates the `pg_trgm` extension, required by ChirpStack v4;
* network: attached only to the internal Docker network — no port is published to the LAN.

The database is internal infrastructure and must not be exposed to the LAN.

PostgreSQL data is included in the infrastructure backup strategy.

---

# 12. Redis

Redis is deployed as a ChirpStack supporting service for cache, queues and metrics.

Verified configuration:

* image: `redis:7-alpine`;
* command:

```text
redis-server --save 300 1 --save 60 100 --appendonly no
```

* RDB snapshots only;
* no AOF;
* persistent volume: `redisdata` mounted at `/data`;
* network: attached only to the internal Docker network — no port is published to the LAN.

It is not a general-purpose application database or message broker.

No application should use Redis for unrelated purposes unless the architecture is explicitly changed.

Redis data is retained as part of the infrastructure persistence strategy, although Redis is not considered equivalent in criticality to PostgreSQL.

---

# 13. Symfony Application

Symfony is the application/business-logic layer.

It is currently **not hosted on the Raspberry Pi**.

The application runs separately on a development laptop and consumes MQTT data from the Raspberry Pi.

Responsibilities include:

* consuming sensor data;
* validating application-level data;
* transforming data when required;
* storing application data;
* implementing business logic;
* eventually controlling IoT actuators.

Symfony should not be moved into this Raspberry Pi repository unless the architecture is deliberately changed.

---

# 14. MySQL

MySQL stores application-level data for Symfony.

It is currently hosted alongside the Symfony development environment.

It is **not the ChirpStack database**.

The separation is intentional:

```text
ChirpStack
    │
    ▼
PostgreSQL

Symfony
    │
    ▼
MySQL
```

ChirpStack infrastructure data and application data therefore remain independent.

The Raspberry Pi infrastructure backup currently covers the Raspberry Pi-hosted infrastructure. Application-level MySQL backups remain the responsibility of the separate development/application environment until that architecture changes.

---

# 15. Docker

All Raspberry Pi infrastructure services run inside Docker.

Use:

```bash
docker compose
```

Do not use the legacy:

```bash
docker-compose
```

The deployment must use ARM64-compatible images.

Containers should use appropriate restart policies so that the infrastructure automatically recovers after a Raspberry Pi reboot.

Typical commands:

```bash
docker compose up -d
docker compose down
docker compose restart
docker compose ps
docker compose logs
```

---

# 16. Repository Structure

The repository currently follows this structure:

```text
/opt/iot/
│
├── docker-compose.yml
├── .env                  # secrets, git-ignored, mode 600
├── .env.example
├── README.md
├── PLAN.md
│
├── docs/
│   └── OPERATIONS.md
│
├── Datasheet/
│   └── LoRaWan/          # hardware datasheets
│
└── configuration/
    │
    ├── chirpstack/
    │   ├── chirpstack.toml
    │   └── region_eu868.toml
    │
    ├── chirpstack-gateway-bridge/
    │   └── chirpstack-gateway-bridge.toml
    │
    ├── mosquitto/
    │   └── config/
    │       ├── mosquitto.conf
    │       ├── passwd          # generated, git-ignored
    │       └── acl
    │
    └── postgresql/
        └── initdb/
            └── 001-chirpstack.sql
```

Secrets such as `.env` and the Mosquitto password file must not be committed to Git.

Operational procedures are documented in:

```text
docs/OPERATIONS.md
```

Backup implementation and operational procedures should also be kept synchronized with the actual systemd service/timer configuration.

---

# 17. Persistence

Important data must never depend exclusively on a container's writable filesystem.

## Persistent data — named Docker volumes

| Volume           | Content                                                       |
| ---------------- | ------------------------------------------------------------- |
| `postgresqldata` | ChirpStack database — critical persistent state               |
| `redisdata`      | Redis RDB snapshots — supporting state                        |
| `mosquittodata`  | MQTT retained messages and subscriptions (`persistence true`) |
| `mosquitolog`    | `mosquitto.log`                                               |

## Configuration — bind mounts

| Path                                                                     | Mounted into               |
| ------------------------------------------------------------------------ | -------------------------- |
| `configuration/chirpstack/`                                              | chirpstack                 |
| `configuration/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml` | chirpstack-gateway-bridge  |
| `configuration/mosquitto/config/`                                        | mosquitto                  |
| `configuration/postgresql/initdb/`                                       | postgres (first init only) |

## Ephemeral container data

Container writable layers and ephemeral container state are not relied upon for persistence.

The infrastructure must survive:

```text
Container recreation
        ↓
Docker restart
        ↓
Raspberry Pi reboot
```

Verified with a full `docker compose down && docker compose up -d` cycle.

Persistent infrastructure data is additionally protected by the automated backup system described in section 24.

---

# 18. Networking

The infrastructure is primarily local.

## Published ports

| Port       | Service                   | Purpose                                                  |
| ---------- | ------------------------- | -------------------------------------------------------- |
| `1883/tcp` | mosquitto                 | MQTT for the laptop (Symfony); anonymous access rejected |
| `8080/tcp` | chirpstack                | Web UI + gRPC API administration from the LAN            |
| `1700/udp` | chirpstack-gateway-bridge | Semtech UDP packet-forwarder endpoint for the LPS8N      |

## Internal only

| Port       | Service    | Notes                                         |
| ---------- | ---------- | --------------------------------------------- |
| `5432/tcp` | postgres   | internal network only                         |
| `6379/tcp` | redis      | internal network only                         |
| `8081/tcp` | chirpstack | monitoring `/health`, used by the healthcheck |

## Docker networks

Two bridge networks are defined:

* `iot-internal` (`internal: true`) — all five services; no internet egress, no published ports. PostgreSQL and Redis exist only on this network.
* `iot-lan` — mosquitto, chirpstack and chirpstack-gateway-bridge; carries the published ports.

Docker cannot publish ports on an `internal` network, which is why the LAN-facing services are attached to both networks.

## Raspberry Pi LAN

External communication over the LAN:

```text
LPS8N
   │
   ▼
Gateway Bridge UDP :1700
```

and:

```text
Laptop
   │
   │ MQTT :1883
   ▼
Mosquitto
```

and:

```text
Laptop / browser
        │
        │ :8080
        ▼
ChirpStack UI / API
```

Database ports are never exposed to the LAN.

Docker's management API must never be exposed.

The infrastructure should not be directly exposed to the Internet.

---

# 19. Security

The Raspberry Pi will eventually control physical devices, therefore security is part of the architecture.

Principles:

* expose the minimum number of ports;
* prefer LAN-only access;
* authenticate MQTT clients where appropriate;
* never expose PostgreSQL unnecessarily;
* never hardcode credentials;
* never commit secrets;
* use least privilege where practical;
* avoid unnecessary container privileges;
* keep container images maintained;
* keep configuration reproducible;
* review exposed ports before adding services.

Backup storage should also not be exposed as a network service unless explicitly required.

---

# 20. Configuration Management

Configuration should be:

* explicit;
* reproducible;
* documented;
* version controlled where appropriate;
* separated from secrets.

Secrets must not be hardcoded into:

* `docker-compose.yml`;
* application source code;
* committed configuration files.

Use:

```text
.env
```

for local secrets when appropriate.

Provide:

```text
.env.example
```

for required variables without including real credentials.

---

# 21. MQTT Architecture

Mosquitto is the central MQTT broker.

## Broker

* host (LAN): the Raspberry Pi IP, port `1883`;
* host (Docker network): `mosquitto:1883`;
* authentication: `allow_anonymous false`;
* users are defined in `configuration/mosquitto/config/passwd`;
* per-topic permissions are defined in `configuration/mosquitto/config/acl`;
* TLS is not currently configured (LAN-only trust; may be added later on a second listener).

## Users and ACLs

| User            | Permissions                                              |
| --------------- | -------------------------------------------------------- |
| `chirpstack`    | read/write `eu868/gateway/#`, read/write `application/#` |
| `gatewaybridge` | read/write `eu868/gateway/#`                             |
| `symfony`       | read-only `application/#`                                |

## Topic structure

Gateway topics:

```text
eu868/gateway/<gateway_id>/event/<event>
eu868/gateway/<gateway_id>/state/<state>
eu868/gateway/<gateway_id>/command/<command>
```

Application topics:

```text
application/<application_id>/device/<dev_eui>/event/<event>
application/<application_id>/device/<dev_eui>/command/<command>
```

The Gateway Bridge publishes with the protobuf marshaler.

The ChirpStack application integration uses JSON (`json = true` in `chirpstack.toml`).

The `eu868` prefix is defined by `topic_prefix` in:

```text
configuration/chirpstack/region_eu868.toml
```

and must match the Gateway Bridge topic templates.

## Gateway direction

```text
LPS8N
   │
   │ Semtech UDP
   ▼
Gateway Bridge
   │
   │ MQTT
   ▼
Mosquitto
   │
   ▼
ChirpStack
```

## Application direction

```text
ChirpStack
   │
   │ MQTT integration
   ▼
Mosquitto
   │
   │ MQTT
   ▼
Symfony
```

The Gateway Bridge and ChirpStack therefore share the same MQTT broker.

The MQTT topic structure must remain aligned with the configured ChirpStack region (`eu868`).

---

# 22. Observability and Troubleshooting

The infrastructure must remain easy to diagnose.

Useful commands:

```bash
docker compose ps
```

```bash
docker compose logs
```

```bash
docker compose logs chirpstack
```

```bash
docker compose logs chirpstack-gateway-bridge
```

```bash
docker compose logs mosquitto
```

MQTT gateway traffic can be inspected with authentication:

```bash
mosquitto_sub -h <pi-ip> -p 1883 \
  -u "$MQTT_CHIRPSTACK_USERNAME" -P "$MQTT_CHIRPSTACK_PASSWORD" \
  -v -t "eu868/gateway/#"
```

This verifies that gateway traffic is reaching the MQTT broker.

When diagnosing a LoRaWAN uplink, verify the pipeline in order:

```text
1. SE01-LB transmits
        ↓
2. LPS8N receives
        ↓
3. LPS8N sends UDP :1700
        ↓
4. Gateway Bridge receives UDP
        ↓
5. Gateway Bridge publishes MQTT
        ↓
6. Mosquitto receives MQTT
        ↓
7. ChirpStack receives the gateway event
        ↓
8. ChirpStack processes the LoRaWAN frame
        ↓
9. ChirpStack publishes application data
        ↓
10. Symfony consumes the MQTT message
```

This order should be preserved during troubleshooting.

---

# 23. Deployment

The infrastructure should be deployable using a small number of reproducible commands.

First-time setup: create `.env` from the template and fill in random secrets.

```bash
cp .env.example .env
```

Generate the Mosquitto password file as documented in:

```text
docs/OPERATIONS.md
```

From the project directory:

```bash
docker compose up -d
```

Check the services:

```bash
docker compose ps
```

Check logs:

```bash
docker compose logs
```

Restart the stack:

```bash
docker compose restart
```

Stop the stack:

```bash
docker compose down
```

The infrastructure should automatically restart after a Raspberry Pi reboot.

---

# 24. Backup and Recovery

The Raspberry Pi infrastructure now has an **automated backup system**.

Backups are designed to protect the persistent IoT infrastructure against accidental deletion, container/data corruption and other recoverable failures.

## 24.1 Backup destination

Backups are stored on separate physical storage mounted at:

```text
/mnt/backup/
```

The IoT backup directory is:

```text
/mnt/backup/iot/
```

The directory itself must remain present. Backup files are created and managed inside this directory.

The backup storage is intentionally separate from the Raspberry Pi's primary application storage.

This separation reduces the risk that a failure of the main storage simultaneously destroys the live infrastructure and its backups.

## 24.2 Backup scheduling

Backups are scheduled using **systemd**, not cron.

The backup system consists of:

```text
systemd timer
      │
      │ scheduled execution
      ▼
iot-backup.service
      │
      ▼
backup script
      │
      ├── backup
      ├── validation
      ├── retention
      └── duplicate protection
```

The service is not expected to remain continuously active.

The systemd timer triggers the backup service according to the configured schedule.

After the backup finishes, the service exits normally.

## 24.3 Backup validation

Creating a backup file is not considered sufficient.

Each backup is validated after creation.

The objective is to detect backup failures immediately rather than discovering an unusable backup during a future recovery operation.

A successful backup therefore requires both:

1. successful backup creation;
2. successful validation.

## 24.4 Retention policy

The current retention policy is:

```text
Daily backups:
    30 days

Monthly backups:
    12 months
```

This provides:

* recent daily recovery points;
* longer-term monthly recovery points;
* controlled disk usage.

Retention is handled automatically by the backup process.

## 24.5 Duplicate protection

The backup process protects against multiple backups being created for the same calendar day.

This is important because manually starting the service or accidentally triggering it more than once must not create unnecessary duplicate daily recovery points.

The intended result is:

```text
2026-08-21
    └── one daily backup

2026-08-22
    └── one daily backup

2026-08-23
    └── one daily backup
```

rather than multiple daily copies.

## 24.6 Backup verification

Useful commands:

```bash
sudo ls -lah /mnt/backup/iot/
```

Check the systemd timer:

```bash
systemctl list-timers --all | grep iot-backup
```

Check the backup service:

```bash
systemctl status iot-backup.service --no-pager
```

Check recent backup logs:

```bash
sudo journalctl -u iot-backup.service --since "today" --no-pager
```

For a complete historical view:

```bash
sudo journalctl -u iot-backup.service --no-pager
```

The expected state after a successful scheduled execution is that the service has completed successfully and returned to an inactive state while the timer remains scheduled for the next execution.

## 24.7 Recovery

The recovery process should conceptually be:

```text
Stop stack
    ↓
Identify required backup
    ↓
Validate backup
    ↓
Restore persistent data
    ↓
Recreate Docker environment if required
    ↓
Start stack
    ↓
Validate PostgreSQL
    ↓
Validate Redis
    ↓
Validate Mosquitto
    ↓
Validate ChirpStack
    ↓
Validate Gateway Bridge
    ↓
Validate LPS8N connectivity
    ↓
Validate sensor data
```

The detailed operational recovery procedure is maintained in:

```text
docs/OPERATIONS.md
```

Recovery should be tested periodically rather than assuming that successful backup creation alone guarantees successful recovery.

## 24.8 Backup philosophy

The backup system follows the principle:

```text
Persistent data
      ↓
Automated backup
      ↓
Validation
      ↓
Separate physical storage
      ↓
Controlled retention
      ↓
Recoverable IoT infrastructure
```

Backups are considered part of the infrastructure rather than an optional operational task.

---

# 25. Development Philosophy

This is a long-term IoT project.

The goal of the first phase is **reliability before complexity**.

The first milestone is:

> Receive real sensor data from the SE01-LB through the LPS8N, process it with ChirpStack, publish it through MQTT, and make it available to Symfony over the local network.

The infrastructure should also be recoverable through automated backups before significant additional complexity is introduced.

Everything else should be introduced progressively.

Do not introduce:

* Kubernetes;
* Kafka;
* additional message brokers;
* additional databases;
* complex monitoring stacks;
* unnecessary microservices;

unless there is a demonstrated technical requirement.

The Raspberry Pi has only 2 GB RAM, so resource efficiency is an explicit architectural consideration.

---

# 26. Phase 1 Scope

## Raspberry Pi

* Debian GNU/Linux 13 ARM64
* Docker
* Docker Compose
* ChirpStack
* ChirpStack Gateway Bridge
* Mosquitto
* PostgreSQL
* Redis
* systemd-based automated backup

## LoRaWAN hardware

* Dragino LPS8N
* Dragino SE01-LB

## Backup infrastructure

* Separate physical backup storage
* Automated daily backups
* Backup validation
* One-backup-per-day protection
* 30-day daily retention
* 12-month monthly retention

## Application environment

* Symfony
* MySQL

## Phase 1 milestone

```text
SE01-LB
   ↓
LPS8N
   ↓
ChirpStack Gateway Bridge
   ↓
Mosquitto
   ↓
ChirpStack
   ↓
Mosquitto
   ↓
Symfony
   ↓
MySQL
```

---

# 27. Future Evolution

The architecture is intended to support additional IoT capabilities without changing the core infrastructure.

Potential future additions include:

* additional LoRaWAN sensors;
* soil monitoring;
* temperature monitoring;
* humidity monitoring;
* automatic irrigation;
* water management;
* aquaponics;
* connected chicken coop;
* solar-power monitoring;
* pumps;
* electrovalves;
* actuators;
* home automation;
* Apple Home / HomeKit integration;
* additional Raspberry Pi nodes;
* a dedicated application server.

The infrastructure layer should remain independent from the application layer.

---

# 28. Rules for GitHub Copilot

When modifying this repository, Copilot must follow these rules:

1. Read this README before making architectural changes.
2. Preserve the separation between IoT infrastructure and application services.
3. Do not move Symfony or MySQL to the Raspberry Pi without an explicit architectural decision.
4. Do not introduce TTN.
5. Do not introduce mandatory cloud IoT services.
6. Do not replace MQTT without a documented technical reason.
7. Keep the LPS8N → Gateway Bridge → Mosquitto → ChirpStack architecture intact.
8. Do not bypass the Gateway Bridge when using the LPS8N's Semtech UDP packet forwarder.
9. Verify changes against the current official ChirpStack documentation.
10. Verify ARM64 compatibility.
11. Prefer Docker Compose over manual host installation.
12. Keep persistent data outside ephemeral containers.
13. Never hardcode secrets.
14. Avoid unnecessary exposed ports.
15. Do not expose PostgreSQL to the LAN without a specific requirement.
16. Do not introduce unnecessary services.
17. Do not assume old ChirpStack configurations remain valid.
18. Check MQTT topic compatibility when changing ChirpStack or Gateway Bridge configuration.
19. Explain the impact of infrastructure changes on the existing architecture.
20. Keep the architecture simple and modular.
21. Consider the Raspberry Pi's 2 GB RAM constraint before adding services.
22. Do not introduce Kubernetes, Kafka, another MQTT broker, or another database without a demonstrated requirement.
23. Do not disable, bypass or replace the automated backup mechanism without an explicit architectural decision.
24. Preserve backup validation and retention policies when modifying backup scripts.
25. Do not change the backup destination without updating this README and the operational documentation.
26. Ensure backup-related changes remain compatible with the separate physical backup storage.
27. Do not consider a backup successful solely because a backup file was created; validation must remain part of the process.
28. Preserve protection against multiple backups for the same calendar day.
29. Keep systemd timer/service configuration and backup documentation synchronized.
30. Prefer simple, recoverable infrastructure over unnecessary complexity.

---

# 29. Authoritative Architecture

The single authoritative Phase 1 architecture diagram is the one in section 4.1 (Current Architecture).

It is intentionally not duplicated elsewhere so that two copies cannot drift apart.

Any future architectural change should be deliberate, documented and justified.

The backup architecture described in section 24 is also part of the current infrastructure design.

---

# References

* [ChirpStack Architecture](https://www.chirpstack.io/docs/architecture.html)
* [ChirpStack Gateway Connection Guide](https://www.chirpstack.io/docs/guides/connect-gateway.html)
* [ChirpStack Gateway Configuration](https://www.chirpstack.io/docs/gateway-configuration/)
* [ChirpStack Gateway Bridge — Semtech UDP](https://www.chirpstack.io/docs/chirpstack-gateway-bridge/backends/semtech-udp.html)
* [ChirpStack Gateway Bridge — MQTT](https://www.chirpstack.io/docs/chirpstack-gateway-bridge/integrations/mqtt.html)
* [ChirpStack — MQTT](https://www.chirpstack.io/docs/chirpstack/backends/mqtt.html)
