# IoT Infrastructure — Raspberry Pi

Local, self-hosted IoT infrastructure based on **LoRaWAN, ChirpStack, MQTT and Docker**.

This repository contains the infrastructure layer of the IoT project running on a dedicated Raspberry Pi.

The application/backend layer is intentionally kept separate and currently runs on a development laptop.

The project is designed to operate **locally**, without The Things Network (TTN) or an external IoT cloud platform.

---

## 1. Project Overview

The objective is to build a reliable and extensible local IoT platform capable of:

* receiving data from LoRaWAN sensors;
* processing LoRaWAN traffic through ChirpStack;
* exposing sensor data through MQTT;
* allowing application services to consume that data;
* eventually controlling physical actuators such as pumps and electrovalves.

The first phase deliberately focuses on the infrastructure required to establish a reliable data pipeline.

### Phase 1

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
* **Prefer official documentation and supported configurations**
* **Avoid unnecessary infrastructure complexity**

The system should remain usable even when Internet connectivity is unavailable, provided the local network and infrastructure remain operational.

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
│                      Docker                             │
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
│   ┌─────────────┐   ┌─────────────┐                     │
│   │ PostgreSQL  │   │    Redis    │                     │
│   └─────────────┘   └─────────────┘                     │
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

The Raspberry Pi currently runs the following Docker services.

| Service                     | Purpose                           |
| --------------------------- | --------------------------------- |
| `chirpstack`                | LoRaWAN Network Server            |
| `chirpstack-gateway-bridge` | Semtech UDP → MQTT gateway bridge |
| `mosquitto`                 | MQTT broker                       |
| `postgres`                  | ChirpStack persistent database    |
| `redis`                     | ChirpStack supporting service     |

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

The database is internal infrastructure and should not normally be exposed to the LAN.

Persistent PostgreSQL data must survive:

* container recreation;
* Docker restart;
* Raspberry Pi reboot.

The required PostgreSQL extensions and initialization are maintained in:

```text
configuration/postgresql/
```

The exact database version should follow the requirements of the deployed ChirpStack version.

---

# 12. Redis

Redis is deployed as a ChirpStack supporting service.

It should not be considered a general-purpose application database or message broker.

Its configuration must follow the requirements of the installed ChirpStack version.

No application should use Redis for unrelated purposes unless the architecture is explicitly changed.

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
├── .env
├── .env.example
├── README.md
│
├── docs/
│   └── OPERATIONS.md
│
└── configuration/
    │
    ├── chirpstack/
    │   ├── chirpstack.toml
    │   └── region_eu868.toml
    │
    ├── chirpstack-gateway-bridge/
    │
    ├── mosquitto/
    │   └── config/
    │
    └── postgresql/
        └── initdb/
```

Secrets such as `.env` and MQTT credentials must not be committed to Git.

Operational procedures are documented in:

```text
docs/OPERATIONS.md
```

---

# 17. Persistence

Important data must never depend exclusively on a container's writable filesystem.

Persistent storage is required for:

* PostgreSQL data;
* Mosquitto data;
* Mosquitto configuration;
* Mosquitto logs where applicable;
* ChirpStack configuration.

The infrastructure must survive:

```text
Container recreation
        ↓
Docker restart
        ↓
Raspberry Pi reboot
```

Persistent Docker volumes or explicitly mounted persistent directories must therefore be used.

---

# 18. Networking

The infrastructure is primarily local.

There are two distinct networking layers.

### Docker network

Used for internal communication between containers:

```text
ChirpStack
Gateway Bridge
Mosquitto
PostgreSQL
Redis
```

### Raspberry Pi LAN

Used for external communication such as:

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
   │ MQTT
   ▼
Mosquitto
```

and, when required:

```text
Laptop / browser
        │
        ▼
ChirpStack UI / API
```

Database ports should not be exposed to the LAN unless there is a specific requirement.

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

The infrastructure uses MQTT in two directions.

### Gateway direction

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

### Application direction

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

The MQTT topic structure must remain aligned with the configured ChirpStack region.

For EU868, the current configuration uses the `eu868` topic prefix.

ChirpStack's documentation notes that the region prefix is significant for MQTT topic configuration in v4.

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

MQTT gateway traffic can be inspected with:

```bash
mosquitto_sub -v -t "+/gateway/#"
```

ChirpStack documents this as a useful way to verify that gateway traffic is reaching the MQTT broker.

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

The infrastructure must be recoverable.

Important persistent data must be identifiable and backed up.

The recovery process should conceptually be:

```text
Stop stack
    ↓
Backup persistent data
    ↓
Recreate Docker environment
    ↓
Restore persistent data
    ↓
Start stack
    ↓
Validate ChirpStack
    ↓
Validate MQTT
    ↓
Validate gateway
    ↓
Validate sensor data
```

The detailed operational backup procedure is maintained in:

```text
docs/OPERATIONS.md
```

Backups should eventually be stored on separate physical storage rather than only on the Raspberry Pi.

---

# 25. Development Philosophy

This is a long-term IoT project.

The goal of the first phase is **reliability before complexity**.

The first milestone is simply:

> Receive real sensor data from the SE01-LB through the LPS8N, process it with ChirpStack, publish it through MQTT, and make it available to Symfony over the local network.

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

### Raspberry Pi

* Debian GNU/Linux 13 ARM64
* Docker
* Docker Compose
* ChirpStack
* ChirpStack Gateway Bridge
* Mosquitto
* PostgreSQL
* Redis

### LoRaWAN hardware

* Dragino LPS8N
* Dragino SE01-LB

### Application environment

* Symfony
* MySQL

### Phase 1 milestone

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

---

# 29. Authoritative Architecture

For Phase 1, the following diagram is the authoritative architecture:

```text
                         LoRaWAN
                            │
                            ▼
                    ┌──────────────┐
                    │    SE01-LB   │
                    │    Sensor    │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │    LPS8N     │
                    │   Gateway    │
                    └──────┬───────┘
                           │
                           │ Semtech UDP
                           │ UDP :1700
                           ▼
┌──────────────────────────────────────────────────────┐
│                    RASPBERRY PI                      │
│                                                      │
│  ┌──────────────────────────────┐                    │
│  │ ChirpStack Gateway Bridge    │                    │
│  │                              │                    │
│  │ Semtech UDP → MQTT           │                    │
│  └──────────────┬───────────────┘                    │
│                 │                                    │
│                 ▼                                    │
│          ┌──────────────┐                            │
│          │  Mosquitto   │                            │
│          │ MQTT Broker  │                            │
│          └──────┬───────┘                            │
│                 │                                    │
│                 ▼                                    │
│          ┌──────────────┐                            │
│          │  ChirpStack  │                            │
│          └──────┬───────┘                            │
│                 │                                    │
│          ┌──────┴──────┐                             │
│          ▼             ▼                             │
│   ┌────────────┐ ┌────────────┐                      │
│   │ PostgreSQL │ │    Redis   │                      │
│   └────────────┘ └────────────┘                      │
│                                                      │
└──────────────────────┬───────────────────────────────┘
                       │
                       │ MQTT
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

This architecture is the baseline for Phase 1.

Any future architectural change should be deliberate, documented and justified.

---

## References

* [ChirpStack Architecture](https://www.chirpstack.io/docs/architecture.html)
* [ChirpStack Gateway Connection Guide](https://www.chirpstack.io/docs/guides/connect-gateway.html)
* [ChirpStack Gateway Configuration](https://www.chirpstack.io/docs/gateway-configuration/)
* [ChirpStack Gateway Bridge — Semtech UDP](https://www.chirpstack.io/docs/chirpstack-gateway-bridge/backends/semtech-udp.html)
* [ChirpStack Gateway Bridge — MQTT](https://www.chirpstack.io/docs/chirpstack-gateway-bridge/integrations/mqtt.html)
* [ChirpStack — MQTT](https://www.chirpstack.io/docs/chirpstack/backends/mqtt.html)
