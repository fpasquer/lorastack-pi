# IoT Infrastructure — Raspberry Pi

Local and scalable IoT infrastructure based on **LoRaWAN, ChirpStack, MQTT and Docker**.

This repository contains the infrastructure running on a dedicated Raspberry Pi.

The application/backend layer is intentionally **not hosted on the Raspberry Pi at this stage**.

---

## 1. Project Overview

The goal of this project is to build a fully local IoT platform capable of collecting data from LoRaWAN sensors and exposing that data to an application layer.

The first phase focuses exclusively on the **IoT infrastructure**.

The Raspberry Pi acts as the permanent IoT server and runs the following services through Docker Compose:

* ChirpStack
* Mosquitto MQTT
* PostgreSQL (ChirpStack database)
* Redis (required by ChirpStack)

The application layer runs separately on a development laptop:

* Symfony
* MySQL

The system must not depend on:

* The Things Network (TTN)
* external IoT cloud platforms
* proprietary cloud services

The system is designed to operate primarily on the local network.

---

# 2. Current Hardware

## Raspberry Pi

Operating system:

```text
Debian GNU/Linux 13 (Trixie)
Architecture: ARM64 / aarch64
```

The Raspberry Pi is intended to operate continuously as the IoT infrastructure server.

## LoRaWAN Gateway

```text
Dragino LPS8N
```

The gateway communicates with ChirpStack over the local network.

## Current LoRaWAN Sensor

```text
Dragino SE01-LB
```

The SE01-LB is the first sensor to be integrated into the platform.

Additional sensors and actuators will be added progressively.

---

# 3. Target Architecture

```text
                         LOCAL NETWORK
                              │
                              │ MQTT
                              │
                    ┌─────────▼─────────┐
                    │      LAPTOP       │
                    │                   │
                    │   Docker Compose  │
                    │                   │
                    │   ┌────────────┐  │
                    │   │  Symfony   │  │
                    │   └─────┬──────┘  │
                    │         │         │
                    │   ┌─────▼──────┐  │
                    │   │   MySQL    │  │
                    │   └────────────┘  │
                    └─────────▲─────────┘
                              │
                              │ MQTT
                              │
                    ┌─────────┴──────────┐
                    │   RASPBERRY PI     │
                    │                    │
                    │      Docker        │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │  ChirpStack  │  │
                    │  └──────┬───────┘  │
                    │         │          │
                    │         ▼          │
                    │  ┌──────────────┐  │
                    │  │   Mosquitto  │  │
                    │  └──────┬───────┘  │
                    │         │          │
                    │  ┌──────▼────────┐ │
                    │  │ ChirpStack DB │ │
                    │  └───────────────┘ │
                    └─────────▲──────────┘
                              │
                           Ethernet
                              │
                    ┌─────────┴─────────┐
                    │       LPS8N       │
                    │      Gateway      │
                    └─────────▲─────────┘
                              │
                           LoRaWAN
                              │
                         ┌────┴────┐
                         │ SE01-LB │
                         └─────────┘
```

---

# 4. Data Flow

The expected data flow is:

```text
SE01-LB
   │
   │ LoRaWAN
   ▼
LPS8N
   │
   │ IP / LAN
   ▼
ChirpStack
   │
   │ MQTT
   ▼
Mosquitto
   │
   │ LAN
   ▼
Symfony
   │
   ▼
MySQL
```

### Responsibilities

### LPS8N

The LPS8N is responsible for receiving LoRaWAN radio traffic and forwarding it to ChirpStack.

It does not contain application logic.

> **TODO:** The exact gateway-to-ChirpStack protocol (UDP packet forwarder vs. ChirpStack MQTT Forwarder) will be decided once the LPS8N is received and configured.

### ChirpStack

ChirpStack is responsible for:

* LoRaWAN network management;
* gateway management;
* device management;
* application management;
* uplinks;
* downlinks;
* LoRaWAN security;
* device data processing;
* MQTT integration.

### Mosquitto

Mosquitto is the local MQTT broker.

It provides the messaging layer between the IoT infrastructure and application services.

### Symfony

Symfony is responsible for application/business logic.

It will consume MQTT data and persist relevant information into MySQL.

Symfony is **not part of this Raspberry Pi repository**.

### MySQL

MySQL stores application-level data.

It is **not part of this Raspberry Pi repository**.

---

# 5. Raspberry Pi Services

The Raspberry Pi must run only the infrastructure services required for the IoT platform.

## Required services

### ChirpStack

LoRaWAN network server.

### Mosquitto

MQTT broker.

### PostgreSQL

PostgreSQL is the database required by the currently supported ChirpStack version (v4).

The exact version must follow the **current official ChirpStack documentation**.

### Redis

Redis is required by ChirpStack for caching and queuing.

It is included **strictly as a ChirpStack dependency**, not as a general-purpose service.

---

# 6. Docker Requirements

All Raspberry Pi services must run inside Docker containers.

Use:

* Docker Engine
* Docker Compose v5
* ARM64-compatible images

Use:

```bash
docker compose
```

Do not use the legacy:

```bash
docker-compose
```

The infrastructure must survive Raspberry Pi reboots.

Containers should use appropriate restart policies.

---

# 7. Persistence

No important application data should be stored exclusively inside ephemeral containers.

Persistent data must use Docker volumes or explicitly mounted persistent directories.

At minimum, persistence is required for:

* ChirpStack database;
* Mosquitto data;
* Mosquitto configuration;
* Mosquitto logs where appropriate;
* ChirpStack configuration.

The infrastructure must be recoverable after:

* container recreation;
* Docker restart;
* Raspberry Pi reboot.

---

# 8. Proposed Directory Structure

The project should use a clean structure similar to:

```text
/opt/iot/
│
├── docker-compose.yml
├── .env
├── README.md
│
├── chirpstack/
│   └── config/
│
├── mosquitto/
│   ├── config/
│   ├── data/
│   └── log/
│
└── database/
    └── ...
```

The structure may be adapted when required by the current official Docker deployment recommendations.

Do not introduce unnecessary directories or services.

---

# 9. Configuration Principles

Configuration must be:

* explicit;
* reproducible;
* documented;
* version controlled where appropriate;
* separated from secrets.

Secrets must not be hardcoded into:

* `docker-compose.yml`;
* source code;
* configuration files committed to Git.

Use `.env` or another appropriate secret-management mechanism for local development.

A `.env.example` should be provided when environment variables are required.

---

# 10. Networking

The infrastructure is primarily local.

Docker networks should be explicitly defined.

Only services that need to communicate externally should expose ports on the Raspberry Pi host.

Internal service-to-service communication should use Docker networking whenever possible.

The following concepts should remain clearly separated:

```text
Docker internal network
        │
        ├── ChirpStack
        ├── Mosquitto
        └── Database

Raspberry Pi LAN interface
        │
        ├── MQTT access when required
        ├── ChirpStack UI/API when required
        └── Gateway communication
```

Do not expose database ports to the LAN unless there is a clear technical requirement.

Do not expose Docker's management API.

Do not expose services directly to the Internet unless explicitly required.

---

# 11. Security

Security is important because the Raspberry Pi will eventually control physical devices.

Follow these principles:

* minimize exposed ports;
* prefer LAN-only access;
* use authentication where appropriate;
* do not expose databases unnecessarily;
* do not hardcode credentials;
* do not commit secrets;
* use least privilege where practical;
* avoid unnecessary Docker privileges;
* document exposed ports;
* keep dependencies and container images maintained.

---

# 12. Version Management

Do not blindly use old tutorials or outdated Docker Compose examples.

Before changing the infrastructure, verify compatibility with the current official documentation for:

* ChirpStack [documentation](https://www.chirpstack.io/docs/);
* Mosquitto [documentation](https://mosquitto.org/documentation/);
* the selected database;
* Docker;
* Docker Compose.

Prefer pinned or explicitly controlled image versions over unbounded `latest` tags for production-like deployments.

ARM64 compatibility must always be considered.

---

# 13. ChirpStack Requirements

The ChirpStack deployment must follow the architecture recommended by the **current official ChirpStack documentation**.

Do not assume that configurations from older ChirpStack releases are still valid.

Before modifying ChirpStack configuration:

1. Identify the current supported version.
2. Verify the official Docker image.
3. Verify the required database.
4. Verify MQTT configuration.
5. Verify gateway communication requirements.
6. Verify ARM64 support.
7. Verify configuration file format.
8. Verify required services and dependencies.

---

# 14. MQTT Requirements

Mosquitto is the central messaging layer.

The MQTT architecture must allow:

```text
ChirpStack
    │
    ▼
Mosquitto
    │
    ├── Symfony
    ├── future services
    └── future IoT applications
```

The MQTT topic structure should remain compatible with ChirpStack's standard MQTT integration unless there is a strong reason to introduce an abstraction layer.

Do not unnecessarily transform or duplicate messages on the Raspberry Pi.

---

# 15. Observability

The infrastructure should be easy to diagnose.

Docker Compose should make it possible to inspect:

```bash
docker compose ps
docker compose logs
docker compose logs chirpstack
docker compose logs mosquitto
```

Health checks should be implemented where they provide meaningful value.

The infrastructure should make it easy to identify:

* container failures;
* database failures;
* MQTT failures;
* ChirpStack failures;
* connectivity problems;
* gateway communication problems.

---

# 16. Deployment

The infrastructure should be deployable using a small number of reproducible commands.

Typical operations should include:

```bash
docker compose up -d
docker compose down
docker compose restart
docker compose ps
docker compose logs
```

Do not require manual installation of application services on the Debian host unless technically unavoidable.

---

# 17. Backup and Recovery

The infrastructure must be designed with migration and recovery in mind.

Important persistent data must be identifiable.

It should be possible to:

1. stop the stack;
2. back up persistent data;
3. recreate the Docker environment;
4. restore the data;
5. restart the infrastructure.

The exact backup procedure should be documented as the project evolves.

---

# 18. Development Philosophy

This is a long-term project.

The first objective is **not** to build the complete IoT platform immediately.

The first objective is to establish a reliable data pipeline:

```text
LoRaWAN Sensor
      ↓
LoRaWAN Gateway
      ↓
ChirpStack
      ↓
MQTT
      ↓
Symfony
      ↓
MySQL
```

Everything else should be introduced progressively.

Avoid premature complexity.

Do not add:

* Kafka;
* Kubernetes;
* additional databases;
* additional message brokers;
* monitoring stacks;

unless there is a demonstrated technical requirement.

---

# 19. Phase 1 Scope

The current phase is limited to:

### Raspberry Pi

* Docker
* Docker Compose
* ChirpStack
* Mosquitto
* PostgreSQL (ChirpStack database)
* Redis (ChirpStack dependency)

### Hardware

* LPS8N
* SE01-LB

### Laptop

* Symfony
* MySQL

The first milestone is:

> Receive real sensor data from the SE01-LB through the LPS8N, process it with ChirpStack, publish it through MQTT, and make it available to Symfony over the local network.

---

# 20. Future Evolution

The architecture should eventually support:

* multiple LoRaWAN sensors;
* soil monitoring;
* temperature and humidity monitoring;
* automatic irrigation;
* water management;
* aquaponics;
* connected chicken coop;
* solar power monitoring;
* pumps;
* electrovalves;
* actuators;
* home automation;
* additional Raspberry Pi nodes;
* potentially a dedicated application server.

The Raspberry Pi infrastructure should therefore remain modular and independent from the application layer.

---

# 21. Rules for GitHub Copilot

When modifying or generating code/configuration in this repository, Copilot must follow these rules:

1. **Read this README before making architectural changes.**
2. Do not introduce services that are outside the current project scope without explaining why.
3. Do not move Symfony or MySQL to the Raspberry Pi.
4. Do not introduce cloud IoT dependencies.
5. Do not introduce The Things Network.
6. Do not replace MQTT with another messaging system without a documented technical reason.
7. Prefer official documentation and current versions.
8. Verify ARM64 compatibility.
9. Prefer Docker Compose over manual host installation.
10. Keep persistent data outside ephemeral containers.
11. Never hardcode secrets.
12. Avoid unnecessary exposed ports.
13. Do not use deprecated Docker Compose syntax.
14. Do not assume old ChirpStack configurations are still valid.
15. When changing infrastructure, explain the impact on the existing architecture.
16. Keep the architecture simple and modular.
17. Preserve the separation between IoT infrastructure and application/backend services.

---

# 22. Current Target

The current target architecture is:

```text
                         LoRaWAN
                            │
                            ▼
                     ┌────────────┐
                     │   LPS8N    │
                     │   Gateway  │
                     └─────┬──────┘
                           │
                           │ LAN
                           ▼
┌─────────────────────────────────────────┐
│             RASPBERRY PI                │
│                                         │
│                 Docker                  │
│                                         │
│  ┌─────────────┐      ┌──────────────┐  │
│  │ ChirpStack  │─────►│  Mosquitto   │  │
│  └──────┬──────┘      └──────┬───────┘  │
│         │                    │          │
│         ▼                    │          │
│  ┌─────────────┐             │          │
│  │ ChirpStack  │             │          │
│  │  Database   │             │          │
│  └─────────────┘             │          │
└──────────────────────────────┼──────────┘
                               │
                            MQTT/LAN
                               │
                               ▼
                     ┌──────────────────┐
                     │      LAPTOP      │
                     │                  │
                     │    Symfony       │
                     │       │          │
                     │       ▼          │
                     │      MySQL       │
                     └──────────────────┘
```

This architecture is the baseline for Phase 1.

Any future architectural change should be deliberate, documented, and justified.
