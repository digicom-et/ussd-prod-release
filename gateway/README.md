# USSD Gateway — Docker Compose

The PROD release package ships a single gateway image (default
`restcomm-ussd-alpine:7.3.1-SNAPSHOT`, an Alpine 3.19 + OpenJDK 8
build that's ~280 MB instead of the heavy ~700 MB Ubuntu variant).

The container runs as `network_mode: host` so the SCTP/MAP stack
binds directly to the host IP. The init service seeds
`/opt/ussdgw/{data,log,configuration}` with the prod config before the
gateway boots.

> **Note:** the production image is still based on the Wildfly 10
> JAIN-SLEE distribution (legacy), so the *current* runtime still uses
> `standalone.conf` for JVM flags and `mgmt-users.properties` for
> management auth. The forward-looking "modern" path is also
> documented below so that when the image moves off Wildfly, the
> switch is a pure config-file rename.

## Image variants

| Variant | Tag | Base image | Approx size |
|---------|-----|------------|-------------|
| **alpine** (default) | `restcomm-ussd-alpine:<VERSION>` | `alpine:3.19` + `openjdk8` | ~280 MB |
| heavy                 | `restcomm-ussd:<VERSION>`       | `eclipse-temurin:8-jdk-jammy` (Ubuntu) | ~700 MB |

Switch via env (or override in `scripts/env.sh`):
```bash
USSDGW_IMAGE_VARIANT=heavy  . scripts/env.sh    # Ubuntu-based
USSDGW_IMAGE_VARIANT=alpine . scripts/env.sh    # Alpine-based (default)
```

The Alpine variant is built by `gateway/build-docker-alpine.sh` using
`gateway/Dockerfile.alpine`.

## Quick start

The gateway lives in a **master `docker-compose.yml` at the package
root** (the old `gateway/docker-compose.yml` was kept only as a
`.legacy.bak` for historical reference).

```bash
# From the package root (image loaded, host dirs created)
cd /opt/ussdgw-prod-release
./scripts/03-start-gateway.sh                    # gateway only
./scripts/03-start-gateway.sh --with-monitor     # + BPF collector (headless)
./scripts/03-start-gateway.sh --tui-only         # foreground TUI dashboard

# Or use the master compose directly:
docker compose -f docker-compose.yml up -d ussdgw
docker compose -f docker-compose.yml up tui       # foreground TUI

# Verify
./scripts/08-check-gateway.sh                    # curl /jolokia/version, logs
docker compose -f docker-compose.yml ps

# Stop
./scripts/04-stop-gateway.sh                     # gateway only
./scripts/04-stop-gateway.sh --all               # gateway + collector + tui
./scripts/stop-all.sh                            # everything incl. AS scripts
```

## Configuration paths

There are **three** ways to configure the gateway, in order of how
recent the layer is. Pick the one that matches your situation.

### 1. JVM flags via `standalone.conf` (current / Wildfly path)

`standalone.conf` is the base JVM layer -- applied by the
`ussdgw` container's entrypoint script. It is **host-mounted** at
`/opt/ussdgw/standalone.conf`, so edits take effect after
`./scripts/03-switch-gateway.sh` (no rebuild needed).

Default flags (excerpt -- see the file for the full set):

```bash
# Heap is NOT set here -- scripts/compute-jvm.sh derives -Xms/-Xmx
# from the container cgroup memory limit at startup.
JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"
JAVA_OPTS="$JAVA_OPTS -Djboss.modules.system.pkgs=org.jboss.byteman"
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"
JAVA_OPTS="$JAVA_OPTS -Duser.timezone=${TZ:-UTC}"

# jSS7 Phase 4 zero-copy integration
JAVA_OPTS="$JAVA_OPTS -Djss7.m3ua.byteBufEnabled=true"
JAVA_OPTS="$JAVA_OPTS -Djss7.sccp.byteBufEnabled=true"
JAVA_OPTS="$JAVA_OPTS -Djss7.asn.nettyEncodeEnabled=true"
JAVA_OPTS="$JAVA_OPTS -Djss7.asn.flatIndexEnabled=true"

# SCTP transport tuning
JAVA_OPTS="$JAVA_OPTS -Dsctp.nodelay=true"
JAVA_OPTS="$JAVA_OPTS -Dsctp.sndbuf=2097152"
JAVA_OPTS="$JAVA_OPTS -Dsctp.rcvbuf=2097152"
```

To add **per-deployment** JVM flags without editing the base file,
set the `USER_CONFIG_JVM` env var in `docker-compose.yml`:

```yaml
environment:
  - USER_CONFIG_JVM=-Djss7.m3ua.byteBufEnabled=true
  - USER_CONFIG_JVM=-Dlog4j2.level=DEBUG
```

(`USER_CONFIG_JVM` is appended last so it overrides anything in
`standalone.conf`.)

### 2. Resource-Adaptor / SLEE config via XML (current / Wildfly path)

The gateway's M3UA / SCCP / TCAP / MAP / USSD behaviour is
configured by the JAIN-SLEE Resource Adaptor XML files in
`config-seed/`. These are **immutable at runtime** -- the
`init` service copies them to `/opt/ussdgw/configuration/` once and
the gateway reads them on boot.

| File | Purpose |
|------|---------|
| `config-seed/configuration/mgmt-users.properties` | Management GUI admin user (default `admin`/`admin`) |
| `config-seed/configuration/mgmt-groups.properties` | Management GUI role groups |
| `config-seed/Mtp3UserPart_m3ua1.xml` | M3UA ASP / SCTP association to the lab HLR (`127.0.0.1:8011`) |
| `config-seed/SccpStack_sccpresource2.xml` | SCCP remote signalling points |
| `config-seed/SccpStack_sccpresource3.xml` | (alt profile) |
| `config-seed/SccpStack_sccprouter2.xml` | SCCP routing rules |
| `config-seed/SccpStack_sccprouter4.xml` | (alt profile) |
| `config-seed/SccpStack_management2.xml` | SCCP stack MBean exposure |
| `config-seed/TcapStack_management.xml` | TCAP dialog / invoke timeout knobs |
| `config-seed/MapStack_management.xml` | MAP dialog timeout + USSD CS timeout |
| `config-seed/SCTPManagement_sctp.xml` | SCTP init / hb / rto / max-burst knobs |
| `config-seed/UssdManagement_ussdproperties.xml` | USSD short codes (`*100#`, `*519#`), per-service MAXCONCURRENTDIALOGS, gRPC AS endpoint |
| `config-seed/UssdManagement_scroutingrule.xml` | USSD service-routing table (short code -> service / virtual-session bridge config) |

To change a knob: edit the relevant XML, then
`./scripts/03-switch-gateway.sh`. Persistent edits in
`/opt/ussdgw/configuration/` survive container restarts.

### 3. `application.properties` (forward-looking / non-Wildfly path)

When the gateway image is rebuilt on top of the `micro-jainslee-core`
runtime (no JAIN-SLEE, no Wildfly), the same knobs move to
`application.properties` -- the standard Spring Boot /
micro-profile-config file. This is what a future release of the
test lab will ship.

**Reference shape** (not yet active in the current image):

```properties
# ---- microjainslee container ----
microjainslee.event-router.buffer-size=2048
microjainslee.event-router.prefer-virtual-threads=true
microjainslee.sbb-pool.min=16
microjainslee.sbb-pool.max=4096
microjainslee.sbb-pool.per-virtual-thread=true

# ---- SCTP transport (was: SCTPManagement_sctp.xml + sctp.* in standalone.conf) ----
sctp.nodelay=true
sctp.sndbuf=2097152
sctp.rcvbuf=2097152

# ---- jSS7 zero-copy (was: -Djss7.* in standalone.conf) ----
jss7.m3ua.byteBufEnabled=true
jss7.sccp.byteBufEnabled=true
jss7.asn.nettyEncodeEnabled=true
jss7.asn.flatIndexEnabled=true

# ---- USSD routing (was: UssdManagement_ussdproperties.xml) ----
ussd.short-codes=*100#,*519#
ussd.service.max-concurrent-dialogs=10000
ussd.virtual-session-bridge.grpc-host=127.0.0.1
ussd.virtual-session-bridge.grpc-port=8443
```

To apply: drop the file at
`/opt/ussdgw/application.properties` (or
`./config-seed/application.properties` before the first install),
restart the container, and the gateway picks it up via the
in-tree `microjainslee-spring-boot-starter` or `adapter-quarkus` bean
producers.

### 4. JVM flags via `USER_CONFIG_JVM` (one-off, survives upgrades)

`USER_CONFIG_JVM` in `docker-compose.yml` is appended after
`standalone.conf` on every container start. Useful for
tracing / debug one-offs without editing the base file:

```yaml
environment:
  # Trace the gRPC client to /tmp/grpc.log:
  - USER_CONFIG_JVM=-Djava.util.logging.config.file=/etc/ussdgw/logging-debug.properties
  # Or pin a single GC thread for forensic debugging:
  - USER_CONFIG_JVM=-XX:+UseSerialGC
```

## Files

| File | Role |
|------|------|
| `docker-compose.yml` | Two services: `init` (seed /opt/ussdgw once) + `ussdgw` (`network_mode: host`) |
| `config-seed/` | Copied to `/opt/ussdgw/config-seed` on first install (then to `configuration/` on first boot) |
| `config-seed/configuration/mgmt-users.properties` + `mgmt-groups.properties` | Wildfly management GUI seed |
| `config-seed/Mtp3UserPart_*.xml`, `SccpStack_*.xml`, `TcapStack_*.xml`, `MapStack_*.xml`, `SCTPManagement_*.xml`, `UssdManagement_*.xml` | JAIN-SLEE Resource Adaptor config (current runtime) |
| `standalone.conf` | Base JVM flags (current runtime) |
| `scripts/host-init.sh` | Runs as `init` service, creates `/opt/ussdgw/{data,log,configuration,patched_jar,config-seed}` |
| `scripts/compute-jvm.sh` | Reads cgroup memory/CPU limits; outputs `-Xms` / `-Xmx` / GC settings |
| `scripts/apply-patched-jars.sh` | Patches deployed jars from `config-seed/patched_jar/` for hot-fixes |
| `scripts/print-banner.sh` | Pretty startup banner with the active release + container id |

## Management GUI

- URL: `http://localhost:8080/ussd-management/`
- User: `admin` / `admin` (seeded from `config-seed/configuration/mgmt-users.properties`)
- Persistence: changes land in `/opt/ussdgw/configuration/` and survive container restarts.

## Healthcheck

The compose healthcheck pings the management endpoint and tolerates
both the legacy `8080/jolokia` and the new management API:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/jolokia/version || curl -fsS -u admin:admin ... || exit 1"]
  interval: 30s
  timeout: 10s
  start_period: 300s
  retries: 10
```

`start_period: 300s` accommodates a cold boot (Wildfly + JAIN-SLEE init
+ APT scan + microjainslee-core warm-up).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `docker compose up` exits 1 on `init` | `/opt/ussdgw` not owned by the compose-user (2000:2000) | `sudo chown -R 2000:2000 /opt/ussdgw` |
| `curl 8080/jolokia/version` times out | gateway still starting (JAIN-SLEE init ~90s) | wait 5 min, then `docker logs -f ussd-prod` |
| MAP USSD dialogs fail with `Connection refused` on `:8012` | SCTP not loaded on host | `sudo modprobe sctp` |
| Container OOM-killed at ~5GB | cgroup memory limit too low | `services.ussdgw.deploy.resources.limits.memory: 8g` in compose |
| `standalone.conf` edits don't take effect | volume mount cached | `./scripts/03-switch-gateway.sh` (recreates the container) |

## Migration to non-Wildfly runtime (roadmap)

When the gateway image moves off Wildfly, the migration order is:

1. Replace `config-seed/Mtp3UserPart_*.xml` etc. with
   `application.properties` keys (see section 3 above).
2. Replace `mgmt-users.properties` / `mgmt-groups.properties` with
   Spring Security `application.properties` user config.
3. Replace `standalone.conf` JVM flags with `USER_CONFIG_JVM` or
   the embedded container's own env (e.g. `JAVA_OPTS` env in
   compose). The current `JAVA_OPTS` list in `standalone.conf` is
   small enough to inline.
4. The `init` service in `docker-compose.yml` can be deleted --
   the modern image will seed config from `/opt/ussdgw/application.properties`
   on every start (idempotent).

Until then, all three paths above work and are documented.
