# IoT Project — Disaster Recovery (DR) Procedure

## Purpose

This document describes how to recover the **IoT / LoRaWAN project** on a replacement Linux host using the backups produced by the Raspberry Pi.

The DR backup contains:

- PostgreSQL database dump
- Mosquitto persistence database
- Mosquitto, PostgreSQL, ChirpStack and Gateway Bridge configuration
- Docker Compose project configuration
- Project files and documentation
- Environment variables and credentials required to recreate the stack

The recovery procedure was validated on an **Azure corporate VM** on 23–24 August 2026.

> **Important:** The Azure VM used for the DR test did not have a public IP. The objective of the test was therefore to validate restoration of the project and its data, not to reconnect the physical LoRaWAN gateway to the VM.

---

## 1. Backup structure

A daily backup is stored under:

```text
/mnt/backup/iot/daily/YYYY-MM-DD/
```

The important files are:

```text
backup-info.txt
.env
docker-compose.yml
postgres.sql.gz
mosquitto.db
configuration.tar.gz
project-files.tar.gz
```

### Backup contents

| File | Purpose |
|---|---|
| `postgres.sql.gz` | Compressed PostgreSQL logical dump of the ChirpStack database |
| `mosquitto.db` | Mosquitto persistence database |
| `configuration.tar.gz` | Mosquitto, PostgreSQL, ChirpStack and Gateway Bridge configuration |
| `docker-compose.yml` | Docker Compose definition used to recreate the services |
| `.env` | Environment variables and service credentials |
| `project-files.tar.gz` | Git/project files, documentation and datasheets |
| `backup-info.txt` | Backup metadata and source information |

---

# 2. Recovery prerequisites

The replacement machine must have:

- Linux
- Docker
- Docker Compose plugin
- Sufficient disk space
- Network access to Docker registries
- Access to the backup files

The recovery host does **not** need to be the original Raspberry Pi.

The DR procedure can be used on another Linux host, including a private/corporate VM.

---

# 3. Create the project directory

On the replacement machine:

```bash
sudo mkdir -p /opt/iot
sudo chown -R "$USER:$USER" /opt/iot

cd /opt/iot
mkdir -p lorastack-pi
```

The expected project location is:

```text
/opt/iot/lorastack-pi
```

---

# 4. Copy the backup to the recovery host

Copy the complete daily backup to the recovery machine.

For example:

```text
/opt/iot/backup/
```

Verify that the expected files exist:

```bash
cd /opt/iot/backup
ls -lh
```

Expected files:

```text
.env
backup-info.txt
configuration.tar.gz
docker-compose.yml
mosquitto.db
postgres.sql.gz
project-files.tar.gz
```

Read the backup metadata:

```bash
cat backup-info.txt
```

Example:

```text
IoT backup
=========

Date:
2026-08-23T03:00:14+01:00

Hostname:
raspberrypi

Backup device:
/dev/sda1

PostgreSQL:
  Database: chirpstack
  Container: iot-postgres-1

Mosquitto:
  Container: iot-mosquitto-1
```

---

# 5. Validate the backup before modifying the project

Always validate the archives before starting the recovery.

## PostgreSQL dump

```bash
cd /opt/iot/backup

gzip -t postgres.sql.gz
echo "postgres gzip: $?"
```

Expected:

```text
postgres gzip: 0
```

## Configuration archive

```bash
tar -tzf configuration.tar.gz >/dev/null
echo "configuration archive: $?"
```

Expected:

```text
configuration archive: 0
```

## Project archive

```bash
tar -tzf project-files.tar.gz >/dev/null
echo "project archive: $?"
```

Expected:

```text
project archive: 0
```

A return code of `0` confirms that the corresponding archive is structurally valid.

---

# 6. Restore the project files

Restore the project archive:

```bash
cd /opt/iot/lorastack-pi

tar -xzf /opt/iot/backup/project-files.tar.gz
```

Check the project:

```bash
ls -la
```

The project should contain files such as:

```text
README.md
PLAN.md
docs/
Datasheet/
```

---

# 7. Restore the Docker Compose configuration

Copy the backed-up Compose file:

```bash
cp /opt/iot/backup/docker-compose.yml \
   /opt/iot/lorastack-pi/docker-compose.yml
```

The Compose definition is the source of truth for the services and volumes that must be recreated.

Check the services:

```bash
cd /opt/iot/lorastack-pi

docker compose config --services
```

Expected services:

```text
mosquitto
postgres
redis
chirpstack
chirpstack-gateway-bridge
```

Check the Docker volumes:

```bash
docker compose config --volumes
```

Expected volumes:

```text
mosquittodata
mosquittolog
postgresqldata
redisdata
```

---

# 8. Restore the environment file

Copy the backup environment file:

```bash
cp /opt/iot/backup/.env \
   /opt/iot/lorastack-pi/.env
```

Protect it:

```bash
chmod 600 /opt/iot/lorastack-pi/.env
```

Check that Compose can resolve its configuration:

```bash
cd /opt/iot/lorastack-pi

docker compose config >/dev/null
echo $?
```

Expected:

```text
0
```

> **Security:** `.env` contains credentials. Never commit it to Git or expose it in documentation.

---

# 9. Restore the service configuration

Restore the complete configuration directory:

```bash
cd /opt/iot/lorastack-pi

tar -xzf /opt/iot/backup/configuration.tar.gz
```

Verify the files:

```bash
find configuration -type f | sort
```

Expected configuration:

```text
configuration/chirpstack/chirpstack.toml
configuration/chirpstack/region_eu868.toml

configuration/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml

configuration/mosquitto/config/acl
configuration/mosquitto/config/mosquitto.conf
configuration/mosquitto/config/passwd

configuration/postgresql/initdb/001-chirpstack.sql
```

Validate the Compose configuration again:

```bash
docker compose config >/dev/null
echo $?
```

Expected:

```text
0
```

---

# 10. Start PostgreSQL first

Start only PostgreSQL:

```bash
docker compose up -d postgres
```

Check:

```bash
docker compose ps postgres
```

Expected:

```text
Up ... (healthy)
```

Check the logs:

```bash
docker logs iot-postgres-1 --tail 50
```

A successful initialization ends with:

```text
PostgreSQL init process complete; ready for start up.
```

and:

```text
database system is ready to accept connections
```

---

# 11. Restore the PostgreSQL database

## Important distinction

The PostgreSQL initialization script:

```text
configuration/postgresql/initdb/001-chirpstack.sql
```

creates the **initial ChirpStack schema** when a new PostgreSQL volume is created.

It does **not** restore the actual production data.

The production data is restored from:

```text
postgres.sql.gz
```

Therefore, a complete DR requires both:

1. PostgreSQL schema initialization
2. Restoration of `postgres.sql.gz`

---

## 11.1 Check the initialized database

Run:

```bash
docker exec iot-postgres-1 \
  psql -U chirpstack -d chirpstack -c '\dt'
```

A correctly initialized database contains the ChirpStack tables, including:

```text
__diesel_schema_migrations
application
device
device_keys
device_profile
gateway
tenant
tenant_user
user
...
```

---

## 11.2 Restore the production dump

For a clean DR installation, restore the logical dump into the newly created database.

First stop ChirpStack if it is running:

```bash
docker compose stop chirpstack chirpstack-gateway-bridge
```

Then restore:

```bash
gzip -dc /opt/iot/backup/postgres.sql.gz | \
docker exec -i iot-postgres-1 \
psql -U chirpstack -d chirpstack
```

Check for errors in the command output.

After the restore, verify the data:

```bash
docker exec iot-postgres-1 psql -U chirpstack -d chirpstack -c "
SELECT
  (SELECT COUNT(*) FROM tenant) AS tenants,
  (SELECT COUNT(*) FROM application) AS applications,
  (SELECT COUNT(*) FROM device) AS devices,
  (SELECT COUNT(*) FROM device_profile) AS device_profiles,
  (SELECT COUNT(*) FROM gateway) AS gateways;
"
```

For the validated 2026-08-23 backup, the expected result was:

```text
 tenants | applications | devices | device_profiles | gateways
---------+--------------+---------+-----------------+----------
       1 |            1 |       1 |               1 |        1
```

Verify the device:

```bash
docker exec iot-postgres-1 psql -U chirpstack -d chirpstack -c "
SELECT name, dev_eui, join_eui, updated_at
FROM device;
"
```

For the validated backup:

```text
SE01-Avocado
```

was present.

---

# 12. Start Redis

Redis does not contain the primary ChirpStack configuration or device inventory.

It is a runtime service used by ChirpStack.

Start it:

```bash
docker compose up -d redis
```

Verify:

```bash
docker compose ps redis
```

Expected:

```text
Up ... (healthy)
```

Test Redis:

```bash
docker exec iot-redis-1 redis-cli ping
```

Expected:

```text
PONG
```

A warning about:

```text
Memory overcommit must be enabled
```

does not prevent Redis from starting, but should be addressed separately on the production recovery host.

---

# 13. Restore Mosquitto

Mosquitto requires both:

- configuration files
- writable data/log directories

The configuration is restored from:

```text
configuration/mosquitto/
```

The Compose file creates:

```text
mosquittodata
mosquittolog
```

If the volumes are newly created, make sure they are writable by the Mosquitto container user.

For the current Mosquitto image this can be fixed with:

```bash
docker run --rm \
  -v iot_mosquittodata:/mosquitto/data \
  -v iot_mosquittolog:/mosquitto/log \
  alpine sh -c '
    chown -R 1000:1000 /mosquitto/data /mosquitto/log
  '
```

Verify:

```bash
docker run --rm \
  -v iot_mosquittodata:/mosquitto/data \
  -v iot_mosquittolog:/mosquitto/log \
  alpine sh -c '
    ls -ld /mosquitto/data
    ls -ld /mosquitto/log
  '
```

The directories should be owned by UID/GID `1000`.

Start Mosquitto:

```bash
docker compose up -d mosquitto
```

Verify:

```bash
docker compose ps mosquitto
```

Expected:

```text
Up ... (healthy)
```

The health check uses the restored `chirpstack` MQTT credentials.

---

# 14. Restore Mosquitto persistence

The backup contains:

```text
mosquitto.db
```

This is Mosquitto's persistence database.

If persistence data is required by the application, copy the backup into the Docker volume after stopping Mosquitto:

```bash
docker compose stop mosquitto
```

Then:

```bash
docker run --rm \
  -v iot_mosquittodata:/mosquitto/data \
  -v /opt/iot/backup:/backup:ro \
  alpine sh -c '
    cp /backup/mosquitto.db /mosquitto/data/mosquitto.db
    chown 1000:1000 /mosquitto/data/mosquitto.db
  '
```

Then restart:

```bash
docker compose up -d mosquitto
```

> The primary application state is stored in PostgreSQL. Mosquitto persistence is supplementary runtime state and should be restored when performing a full DR.

---

# 15. Start ChirpStack

Once PostgreSQL, Redis and Mosquitto are healthy:

```bash
docker compose up -d chirpstack
```

Check:

```bash
docker compose ps chirpstack
```

Expected:

```text
Up ... (healthy)
```

Check logs:

```bash
docker logs iot-chirpstack-1 --tail 50
```

Successful startup should show:

```text
Applying schema migrations
```

followed by successful PostgreSQL, Redis and MQTT initialization.

The API should be listening on:

```text
0.0.0.0:8080
```

---

# 16. Start ChirpStack Gateway Bridge

Start:

```bash
docker compose up -d chirpstack-gateway-bridge
```

Verify:

```bash
docker compose ps chirpstack-gateway-bridge
```

Expected:

```text
Up
```

Check logs:

```bash
docker logs iot-chirpstack-gateway-bridge-1 --tail 50
```

A successful startup contains:

```text
starting ChirpStack Gateway Bridge
```

and:

```text
starting gateway udp listener addr="0.0.0.0:1700"
```

and:

```text
integration/mqtt: connected to mqtt broker
```

---

# 17. Final system validation

Run:

```bash
docker compose ps
```

The complete stack should contain:

```text
iot-postgres-1
iot-redis-1
iot-mosquitto-1
iot-chirpstack-1
iot-chirpstack-gateway-bridge-1
```

Expected state:

```text
postgres                     healthy
redis                        healthy
mosquitto                    healthy
chirpstack                   healthy
gateway-bridge               running
```

---

## 17.1 Validate PostgreSQL data

```bash
docker exec iot-postgres-1 psql -U chirpstack -d chirpstack -c "
SELECT
  (SELECT COUNT(*) FROM tenant) AS tenants,
  (SELECT COUNT(*) FROM application) AS applications,
  (SELECT COUNT(*) FROM device) AS devices,
  (SELECT COUNT(*) FROM device_profile) AS device_profiles,
  (SELECT COUNT(*) FROM gateway) AS gateways;
"
```

For the validated backup:

```text
1 tenant
1 application
1 device
1 device profile
1 gateway
```

The device must be:

```text
SE01-Avocado
```

---

## 17.2 Validate MQTT

Check Mosquitto:

```bash
docker compose ps mosquitto
```

Then inspect recent logs:

```bash
docker logs iot-mosquitto-1 --tail 30
```

A successful health check produces a connection similar to:

```text
New client connected ... as healthcheck ... u'chirpstack'
```

---

## 17.3 Validate ChirpStack

Check:

```bash
docker compose ps chirpstack
```

Then:

```bash
docker logs iot-chirpstack-1 --tail 50
```

Look for:

```text
Setting up PostgreSQL connection pool
Setting up Redis client
Initializing MQTT integration
Starting MQTT event loop
Setting up API interface bind=0.0.0.0:8080
```

---

## 17.4 Validate Gateway Bridge

Check:

```bash
docker logs iot-chirpstack-gateway-bridge-1 --tail 30
```

Expected:

```text
starting ChirpStack Gateway Bridge
starting gateway udp listener
integration/mqtt: connected to mqtt broker
```

---

# 18. Full-stack restart test

After the recovery has been validated individually, test that the complete stack can be recreated normally:

```bash
docker compose down
```

Then:

```bash
docker compose up -d
```

Check:

```bash
docker compose ps
```

All services should start through their dependency chain.

If a service fails, troubleshoot it before considering the DR successful.

---

# 19. Physical gateway limitation

The DR test performed on the corporate Azure VM validates:

- Docker Compose recreation
- PostgreSQL restoration
- ChirpStack restoration
- Redis startup
- Mosquitto restoration
- Gateway Bridge startup
- configuration restoration
- project file restoration

However, the VM is a **corporate machine without a public IP**.

Therefore, the physical LoRaWAN gateway cannot necessarily be redirected to this VM from the Internet.

This is a **networking limitation of the DR test environment**, not a failure of the application recovery.

The recovered IoT stack itself is operational.

To resume LoRaWAN traffic after a real disaster, the replacement host must additionally provide an appropriate network path from the physical gateway to:

```text
Gateway
   |
   | Semtech UDP
   v
UDP 1700
   |
   v
ChirpStack Gateway Bridge
   |
   | MQTT
   v
Mosquitto
   |
   v
ChirpStack
```

The exact networking solution depends on the infrastructure available at the time of the disaster.

---

# 20. What is actually recovered?

After completing this procedure, the following project state is recovered:

### Application state

- ChirpStack tenant
- Application
- Device
- Device profile
- Gateway
- Device credentials and configuration stored in PostgreSQL
- ChirpStack database schema

### Infrastructure

- PostgreSQL
- Redis
- Mosquitto
- ChirpStack
- ChirpStack Gateway Bridge
- Docker Compose networking
- Docker volumes

### Configuration

- ChirpStack configuration
- EU868 region configuration
- Gateway Bridge configuration
- Mosquitto configuration
- Mosquitto users/password database
- Mosquitto ACL

### Project

- README
- PLAN
- Operations documentation
- Datasheets
- Project files

---

# 21. What is NOT automatically recovered?

The DR backup does not magically recreate external infrastructure.

The following may require manual configuration:

- DNS
- Firewall rules
- Public IP / routing
- VPN
- Physical LoRaWAN gateway network configuration
- External monitoring
- External DNS records
- Cloud-specific infrastructure
- Any application or service not included in this backup

In particular, the corporate Azure VM used during the DR test had no public IP, so reconnecting the physical gateway was outside the scope of this validation.

---

# 22. DR success criteria

The DR is considered successful when all of the following are true:

- [x] Backup archives are readable
- [x] PostgreSQL dump passes `gzip -t`
- [x] Configuration archive passes `tar -tzf`
- [x] Project archive passes `tar -tzf`
- [x] Docker Compose configuration is valid
- [x] PostgreSQL starts successfully
- [x] ChirpStack database schema is present
- [x] PostgreSQL production data is restored
- [x] Tenant count is correct
- [x] Application count is correct
- [x] Device count is correct
- [x] Device profile count is correct
- [x] Gateway count is correct
- [x] `SE01-Avocado` is present
- [x] Redis starts and is healthy
- [x] Mosquitto starts and is healthy
- [x] ChirpStack starts and is healthy
- [x] Gateway Bridge starts
- [x] Gateway Bridge connects to MQTT
- [x] Full Docker Compose stack starts successfully

The August 2026 recovery test validated these application-level recovery criteria.

---

# 23. Quick recovery checklist

For an experienced operator, the recovery sequence is:

```bash
# 1. Create project
sudo mkdir -p /opt/iot
sudo chown -R "$USER:$USER" /opt/iot
mkdir -p /opt/iot/lorastack-pi

# 2. Restore project
cd /opt/iot/lorastack-pi
tar -xzf /opt/iot/backup/project-files.tar.gz

# 3. Restore Compose and environment
cp /opt/iot/backup/docker-compose.yml .
cp /opt/iot/backup/.env .
chmod 600 .env

# 4. Restore configuration
tar -xzf /opt/iot/backup/configuration.tar.gz

# 5. Validate Compose
docker compose config

# 6. Start PostgreSQL
docker compose up -d postgres

# 7. Restore PostgreSQL
gzip -dc /opt/iot/backup/postgres.sql.gz | \
docker exec -i iot-postgres-1 \
psql -U chirpstack -d chirpstack

# 8. Start Redis
docker compose up -d redis

# 9. Fix Mosquitto volume permissions if required
docker run --rm \
  -v iot_mosquittodata:/mosquitto/data \
  -v iot_mosquittolog:/mosquitto/log \
  alpine sh -c 'chown -R 1000:1000 /mosquitto/data /mosquitto/log'

# 10. Start Mosquitto
docker compose up -d mosquitto

# 11. Start ChirpStack
docker compose up -d chirpstack

# 12. Start Gateway Bridge
docker compose up -d chirpstack-gateway-bridge

# 13. Verify
docker compose ps
```

---

# 24. Recovery principle

The backup is designed so that the IoT project can be rebuilt on a new host rather than relying on the original Docker volumes.

The critical recovery chain is:

```text
Backup
  |
  +-- project-files.tar.gz
  |
  +-- docker-compose.yml
  |
  +-- .env
  |
  +-- configuration.tar.gz
  |
  +-- postgres.sql.gz
  |
  +-- mosquitto.db
          |
          v
   New Linux host
          |
          v
      Docker Compose
          |
          +-- PostgreSQL
          |      |
          |      +-- ChirpStack schema
          |      +-- restored application data
          |
          +-- Redis
          |
          +-- Mosquitto
          |
          +-- ChirpStack
          |
          +-- Gateway Bridge
          |
          v
    Recovered IoT stack
```

The most important recovery artifact is the **PostgreSQL logical dump**, because it contains the persistent ChirpStack application state. The configuration archive and Compose definition then recreate the infrastructure around that state.
