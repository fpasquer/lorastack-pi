# IoT Project Plan — resume point

**Status: Phases 1–5 COMPLETE, deployed and validated (2026-08-16).**
**Next: Phase 6 — LPS8N gateway (not started; do not touch the gateway yet unless resuming).**

Host: Raspberry Pi 4 (2 GB), Debian 13 (Trixie) ARM64, Docker 29.7.2 +
Compose v5.4.0, LAN IP 192.168.1.16, USB SSD. Stack lives in /opt/iot
(docker-compose.yml + configuration/ + .env + docs/OPERATIONS.md).
Full operational details: see [docs/OPERATIONS.md](docs/OPERATIONS.md).

---

## Decisions (user-approved)

- Gateway protocol: **Semtech UDP packet forwarder** on the LPS8N →
  **chirpstack-gateway-bridge** container on the Pi (UDP 1700 ↔ MQTT,
  topic prefix `eu868`). Correction during implementation: ChirpStack v4
  has NO built-in UDP backend (gateway backend is MQTT only), so the
  bridge container is required — this is the official architecture.
- Host: Pi 4 / 2 GB RAM, Debian 13 ARM64.
- Pi LAN address: DHCP reservation on router (192.168.1.16).
- Region / activation: **EU868 + OTAA** (LoRaWAN 1.0.3 Class A).
- Minimal architecture: only ChirpStack, gateway-bridge, PostgreSQL,
  Redis, Mosquitto. No monitoring/proxy extras.
- No aggressive DB/Redis tuning yet — measure first
  (`free -h`, `docker stats --no-stream`, `df -h`), then optimize.

## Current stack (deployed)

| Service | Image | Ports |
|---|---|---|
| chirpstack | chirpstack/chirpstack:4 | 8080/tcp → LAN (UI/API) |
| chirpstack-gateway-bridge | chirpstack/chirpstack-gateway-bridge:4 | 1700/udp → LAN (for LPS8N) |
| postgres | postgres:16-alpine | internal only (pg_trgm installed) |
| redis | redis:7-alpine | internal only |
| mosquitto | eclipse-mosquitto:2 | 1883/tcp → LAN, auth + ACL enforced |

Networks: `iot-internal` (internal: true — postgres/redis only) +
`iot-lan` (published ports). NOTE: Docker does not publish ports on
internal networks — this split is deliberate.

Secrets: all in `.env` (0600, git-ignored), incl. reference copy of the
ChirpStack UI admin password (`CHIRPSTACK_ADMIN_PASSWORD`). Placeholders
in `.env.example`.

Validated: all healthy; migrations applied; ChirpStack connected to
PostgreSQL/Redis/Mosquitto; anonymous MQTT rejected; symfony user
publish blocked by ACL; UI HTTP 200 on LAN; UDP 1700 listening;
5432/6379 unreachable from LAN; persistence survives full down/up.

## Hardware facts (Dragino official docs)

Note: the local datasheet PDFs could not be parsed in-session; facts
below came from Dragino's current online manuals. When convenient,
verify against /opt/iot/Datasheet/LoRaWan/*.pdf (e.g. `pdftotext`).

### LPS8N
- SX1302 concentrator, 8 channels. 868 SKU has 863–870 MHz RF filter —
  must be the 868 variant for EU868.
- Forwarders: Semtech UDP (chosen), Basic Station, optional MQTT
  forwarder .ipk. Nothing installed on the gateway in our design.
- Access: factory WiFi AP `dragino-xxxxxx` (pw `dragino+dragino`),
  IP 10.130.1.1; WAN Ethernet DHCP; WAN fallback 172.31.255.254
  (PC: 172.31.255.253/30). Web UI: http://IP or http://IP:8000,
  `root/dragino` (or `admin/dragino`); SSH 22 (AP) / 2222 (WAN).
- Power: 5V/2A USB-C. SYS LED: solid blue = LoRaWAN server connected;
  blinking blue = internet but no LoRaWAN conn / booting; red = no
  internet.
- **GOTCHA: "Internet Detect" (System → General) is enabled by default
  and reboots the gateway every 15 min without internet — must be
  disabled/set to manual in this LAN-only deployment.**
- Gateway ID (EUI) is on the LoRaWAN page — needed for ChirpStack
  registration.

### SE01-LB
- LoRaWAN 1.0.3 Class A, OTAA default, pre-loaded unique keys
  (DevEUI sticker + DevEUI/AppEUI/AppKey registration sheet; AppEUI is
  entered as JoinEUI). Band-specific firmware — must be EU868.
- Measures soil moisture (%), soil temperature, soil conductivity (EC);
  FDR method, calibrated for saline-alkali/loamy/mineral soil.
- Default uplink every 20 min (AT+TDC or downlink `0x01`+3-byte seconds).
- Uplink payload (MOD=0 default): 11 bytes = BAT(2, mV) + DS18B20(2,
  /10 signed; 0x0CCC = not connected) + moisture(2, /100 → %) +
  soil temp(2, /100 signed) + EC(2, uS/cm) + flags(1: MOD bit7,
  count_mod, i_flag, s_flag). Counting mode adds 4-byte count → 15 B.
- Device status on FPort=5; datalog on FPort=3; main sensor uplink
  FPort=2 (verify in local PDF).
- JS decoder: github.com/dragino/dragino-end-node-decoder (works in
  ChirpStack device-profile codec).
- Downlinks: `0x01` TDC, `0x04FF` reset, `0x05` CFM, `0x06` INTMOD,
  `0x0A` MOD, `0x26 01` request device status.
- Battery ER26500+SPC1520 (8500 mAh), ~5 y at default interval.
- Activation: button >3 s to join (green LED). 5× press = deep sleep.

## Remaining phases

### Phase 6 — LPS8N gateway (NEXT)
- Reserve a DHCP address for the LPS8N on the router; note it.
- Connect LPS8N WAN Ethernet to the LAN; find its IP; log into web UI
  (root/dragino) and **change the password**.
- **Disable "Internet Detect" (System → General)** — otherwise 15-min
  reboot loop.
- Set LoRa frequency plan EU868 (confirm 868 SKU).
- LoRaWAN → Semtech UDP: server address 192.168.1.16, uplink/downlink
  port 1700.
- In ChirpStack UI: register gateway with its Gateway ID (EUI), eu868.
- Apply the DOCKER-USER iptables rule restricting 1700/udp to the
  LPS8N IP (exact command in docs/OPERATIONS.md §3).
- Expected: gateway "online" (recent last-seen) in ChirpStack;
  LPS8N LogRead shows PULL_ACK traffic.

### Phase 7 — SE01-LB device
- ChirpStack: create device profile (LoRaWAN 1.0.3, Class A, OTAA,
  EU868, regional params RP002-1.0.3) with the Dragino JS codec
  (dragino-end-node-decoder); create application; register device with
  DevEUI / JoinEUI (AppEUI) / AppKey from the registration sheet.
- Press sensor button >3 s to join.
- Expected: JoinAccept + uplinks every 20 min with decoded fields
  (bat, soil moisture %, soil temp, EC). Cross-check one raw 11-byte
  frame by hand.

### Phase 8 — MQTT validation
- From laptop: subscribe `application/+/device/+/event/up` as the
  `symfony` user against 192.168.1.16:1883.
- Force an uplink (button 1–3 s) and verify JSON envelope, decoded
  object, fPort, and base64 raw payload = the 11-byte frame.
- Re-verify: symfony cannot publish; anonymous rejected.

### Phase 9 — Symfony integration (laptop, separate repo)
- Symfony + MySQL compose on laptop; MQTT client subscribing to the
  application topics with the `symfony` credentials; persist decoded
  readings to MySQL.
- Contract (documented in docs/OPERATIONS.md): topic scheme
  `application/<app_id>/device/<dev_eui>/event/up`, JSON encoding,
  broker 192.168.1.16:1883, symfony user is subscribe-only.

## Pending follow-ups (small, any time)

- Consider rotating the ChirpStack UI password once (it passed through
  the chat) and updating the `.env` reference copy.
- TLS on a second Mosquitto listener (8883) if the LAN is not fully
  trusted (documented, not done).
- Resource measurement pass (`free -h`, `docker stats --no-stream`,
  `df -h`) before any tuning.
- Verify SE01-LB main uplink FPort against the local datasheet PDF.
