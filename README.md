# nut-plus - Network UPS Tools (NUT) with Email notifications, Proxmox API shutdown, UNAS-Pro API shutdown and WoL support -- oriented towards use with Portainer

This Docker implementation of Network UPS Tools is oriented towards use with Portainer via a Docker Compose YAML. Installation can typically be done using only env vars, with no editing of the compose itself.

## Key Features

**Power Management Automation:**
Monitors one or more UPS devices connected via USB and gracefully shuts down the Docker host during prolonged outages -- without requiring modifications to the host OS. Email notifications for power events (on battery, power restored, shutdown initiated) are sent via Gmail's SMTP service.

**Flexible Deployment:**
Operates in two roles -- as a primary (master) connected directly to the UPS via USB, or as a secondary (slave) monitoring a primary instance over the network. Multiple secondaries can monitor a single primary.

**Shutdown Thresholds:**
Shutdown can be triggered by a configurable time delay (`SYSTEM_DELAY_SHUTDOWN`), a remaining runtime threshold (`BATTERY_RUNTIME_LOW`), or a battery charge percentage threshold (`BATTERY_CHARGE_LOW`) -- whichever occurs first.

**Proxmox Integration:**
Supports graceful Proxmox node shutdown via API tokens with the `Sys.PowerMgmt` privilege, enabling coordinated cluster shutdowns before the Docker host powers off. Supports one-to-one host/node/token arrays, or a single host and token with multiple nodes.

**UniFi UNAS-Pro Integration:**
Supports graceful shutdown of one or more UNAS-Pro devices via their session-based API before the Docker host powers off. Rather than using an existing administrator account, create a dedicated user on each UNAS-Pro for this purpose, with a unique password used nowhere else. As of this writing, UNAS-Pro's role options don't offer granular permissions below admin-level access -- a dedicated account still limits blast radius (a compromised credential doesn't expose your main admin login) even though it can't be scoped down to poweroff-only.

**Recovery Capabilities:**
Upon power restoration, the container can send Magic Packets to wake previously shutdown systems via [WoLweb](https://hub.docker.com/r/bnhf/wolweb), extending UPS battery life by avoiding complete discharge before systems come back online.

## Companion Services

**[nut-cgi-plus](https://hub.docker.com/r/bnhf/nut-cgi-plus):** A companion web interface displaying live UPS status across multiple nut-plus instances. Configure it with `UPSHOSTS` and `UPSNAMES` pointing at your nut-plus containers.

**[WoLweb](https://hub.docker.com/r/bnhf/wolweb):** A Wake-on-LAN utility with web interface, used by nut-plus to wake systems after power is restored.

## Configuration

The YAML below is intended to be self-documenting and typically requires no editing. Use the `Environment variables` section of Portainer for all installation-specific values:

> **Upgrading an existing stack:** if your current environment variables have `NUT_USB=auto`, change it to `NUT_USB=` (blank) before redeploying -- the `devices:` section now reuses this variable directly, and `auto` is no longer a valid value there.

```yaml
services:
  nut-plus: # This docker-compose typically requires no editing. Use the Environment variables section of Portainer to set your values.
    # 2026.08.01
    # GitHub home for this project: https://github.com/bnhf/nut-plus.
    # Docker container home for this project with setup instructions: https://hub.docker.com/r/bnhf/nut-plus.
    image: bnhf/nut-plus:${TAG:-latest} # Add the tag like latest or test to the environment variables below.
    container_name: nut-plus
    hostname: ${HOSTNAME} # Set a unique hostname per instance -- used in email notifications.
    dns_search: ${DOMAIN:-localdomain} # LAN domain for hostname resolution (e.g. local, localdomain). Optionally append a Tailnet domain space-separated.
    devices:
      - ${NUT_USB:-/dev/null} # Specific USB device path override (e.g. /dev/usb/hiddev0). Leave blank unless bypassing bus auto-detection -- defaults to /dev/null, which always exists.
      - ${NUT_SCAN:-/dev/null} # Parent directory for USB device nodes, used by nut-scanner for auto-detection. Leave blank for secondaries or hosts with no USB controller -- defaults to /dev/null. Primaries: set NUT_SCAN=/dev/bus/usb.
    ports:
      - ${HOST_PORT:-3493}:3493 # Use the standard NUT port of 3493, or optionally change it if it's in use on your Docker host. Default=3493.
    environment:
      - NUT_PLUS_COMPOSE=2026.08.01 # Do not change this value.
      # ── Identity ────────────────────────────────────────────────────────────
      - UPSNAME=${UPSNAME} # Sets a name for the UPS (1 to 8 chars), used in email notifications.
      - TZ=${TZ} # Timezone, e.g. America/Denver.
      # ── UPS connectivity ────────────────────────────────────────────────────
      # On secondaries set NUT_MODE=netclient, MASTER_SLAVE=slave, and NUT_HOST to the primary's hostname or IP. No need to modify the devices section.
      - NUT_MODE=${NUT_MODE:-standalone} # standalone, netserver, or netclient. See https://networkupstools.org/docs/man/nut.conf.html.
      - NUT_HOST=${NUT_HOST:-localhost} # Hostname or IP of the NUT server to monitor. Leave as localhost for standalone/netserver (primary); set to the primary's address for netclient (secondary).
      - NUT_DRIVER=${NUT_DRIVER:-scanner} # Specify a NUT driver to use, or use scanner to let nut-scanner identify the connected UPS.
      - NUT_USB=${NUT_USB:-auto} # Leave as auto, or specify a USB device path override.
      - NUT_SERIAL=${NUT_SERIAL} # If multiple UPS units are attached to this host (one container per unit), set this to the serial number of the unit this container should claim. Leave blank when only one UPS is on this host.
      - MASTER_SLAVE=${MASTER_SLAVE} # master if directly connected to the UPS, slave if not.
      - NUT_USER=${NUT_USER:-admin} # Username for this NUT instance (full access).
      - NUT_PASSWORD=${NUT_PASSWORD} # Password for the full access user (required).
      - NUT_SLAVE_USER=${NUT_SLAVE_USER:-upsmon} # Username for slave/secondary connections to this NUT instance (limited access).
      - NUT_SLAVE_PASSWORD=${NUT_SLAVE_PASSWORD} # Password for the slave user.
      # ── Shutdown thresholds ─────────────────────────────────────────────────
      - POLLTIME=${POLLTIME} # Interval (in seconds) at which NUT polls the UPS for status (default=60).
      - SYSTEM_DELAY_SHUTDOWN=${SYSTEM_DELAY_SHUTDOWN:-90} # Sets the time in seconds from when a power failure is detected until a system shutdown is initiated (default=90).
      - UPS_DELAY_SHUTDOWN=${UPS_DELAY_SHUTDOWN:-180} # Sets the time in seconds from when "shutdown.return" is sent to the UPS until it powers off (default=180).
      - BATTERY_RUNTIME_LOW=${BATTERY_RUNTIME_LOW} # Sets the threshold in seconds for the UPS to declare "LB", resulting in an immediate shutdown (optional).
      - BATTERY_CHARGE_LOW=${BATTERY_CHARGE_LOW} # Sets the battery charge percentage threshold for the UPS to declare "LB", resulting in an immediate shutdown (optional).
      - FINALDELAY=${FINALDELAY:-5} # Last sleep interval in seconds before executing SHUTDOWNCMD (default=5).
      - HOSTSYNC=${HOSTSYNC:-15} # How long upsmon will wait before giving up on another upsmon (default=15).
      - SHUTDOWNCMD=${SHUTDOWNCMD} # upsmon runs this command when the system needs to be brought down.
      # ── Event handling ───────────────────────────────────────────────────────
      - NOTIFYCMD=${NOTIFYCMD} # upsmon calls this to send messages when things happen.
      - NOTIFYFLAG_ONBATT=${NOTIFYFLAG_ONBATT} # Leave blank if using LOWBATT shutoff only, EXEC for timed shutoff. Use SYSLOG, WALL or EXEC otherwise. For more than one, join with a plus sign (e.g. SYSLOG+EXEC).
      - NOTIFYFLAG_ONLINE=${NOTIFYFLAG_ONLINE} # Leave blank if using LOWBATT shutoff only, EXEC for power-restored actions. For more than one, join with a plus sign (e.g. SYSLOG+EXEC).
      - NOTIFYFLAG_LOWBATT=${NOTIFYFLAG_LOWBATT} # Leave blank for timed shutoff only. Use SYSLOG or WALL otherwise. For more than one, join with a plus sign (e.g. SYSLOG+WALL).
      - CMDSCRIPT=${CMDSCRIPT:-/etc/nut/upssched-cmd} # This script gets called to invoke commands for timers that trigger.
      - MAXAGE=${MAXAGE:-15} # After a UPS driver has stopped updating data for this many seconds, upsd marks it stale (default=15).
      # ── Maintenance ──────────────────────────────────────────────────────────
      - UPDATE_CONFIGS=${UPDATE_CONFIGS:-true} # Set to true to keep all included NUT .conf files updated. Recommended (default=true).
      # ── Email notifications via Gmail SMTP ──────────────────────────────────
      - SMTP_GMAIL=${SMTP_GMAIL} # Gmail account (with 2FA enabled) to use for SMTP.
      - GMAIL_APP_PASSWD=${GMAIL_APP_PASSWD} # App password from Gmail account being used for SMTP.
      - NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL} # The Email account to receive on/off battery messages and other notifications.
      - POWER_RESTORED_EMAIL=${POWER_RESTORED_EMAIL} # Set to true if you'd like an Email notification when power is restored after UPS shutdown.
      # ── Wake-on-LAN via WoLweb ──────────────────────────────────────────────
      - WOLWEB_HOSTNAMES=${WOLWEB_HOSTNAMES} # Space-separated list of hostnames to send WoL Magic Packets to on startup.
      - WOLWEB_PATH_BASE=${WOLWEB_PATH_BASE} # Everything after http:// and before the /hostname required to wake a system with WoLweb e.g. raspberrypi6:8089/wolweb/wake.
      - WOLWEB_DELAY=${WOLWEB_DELAY:-0} # Seconds to delay before sending WoL Magic Packets to WOLWEB_HOSTNAMES (default=0).
      # ── Proxmox shutdown via API ─────────────────────────────────────────────
      - PVE_SHUTDOWN_HOSTS=${PVE_SHUTDOWN_HOSTS} # Ordered list of pve hostnames (or IPs) to be used for API shutdown. Used with matching lists of PVE_SHUTDOWN_NODES and PVE_SHUTDOWN_TOKENS.
      - PVE_SHUTDOWN_NODES=${PVE_SHUTDOWN_NODES} # Ordered list of pve nodes. Used with matching lists of PVE_SHUTDOWN_HOSTS and PVE_SHUTDOWN_TOKENS.
      - PVE_SHUTDOWN_TOKENS=${PVE_SHUTDOWN_TOKENS} # Ordered list of pve API tokens with secrets in the form <username>@<realm>!<tokenid>=<secret>.
      # ── UniFi UNAS-Pro shutdown via API ──────────────────────────────────────
      - UNAS_SHUTDOWN_HOSTS=${UNAS_SHUTDOWN_HOSTS} # Space-separated list of UNAS-Pro devices to shut down, each in the form username:password@host (password may contain @ or : characters).
    healthcheck:
      test: ["CMD-SHELL", "upsc ${UPSNAME}@${NUT_HOST:-localhost} 2>&1 | grep -q 'ups.status'"] # Command to check health.
      interval: ${HC_INTERVAL:-30s} # Interval between health checks. Default=30s.
      timeout: ${HC_TIMEOUT:-5s} # Timeout for each health check. Default=5s.
      retries: ${HC_RETRIES:-3} # How many times to retry. Default=3.
      start_period: ${HC_START_PERIOD:-15s} # Estimated time to boot. Default=15s.
    volumes:
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket # Required to support host shutdown from the container.
      - /etc/localtime:/etc/localtime:ro # Syncs the container's clock/timezone with the host so syslog timestamps use local time.
      - ${HOST_DIR}/nut:/etc/nut # /etc/nut can be bound to a directory or a docker volume.
    restart: unless-stopped
```

And here's a set of sample env vars, which can be copy-and-pasted into Portainer in `Advanced mode`. In that mode it's quick-and-easy to modify those values for your use. Refer to the comments in the compose for clarification on how a given variable is used:

```
TAG=latest
HOSTNAME=RPi5_nut
DOMAIN=localdomain
NUT_SCAN=/dev/bus/usb
HOST_PORT=3493
HC_INTERVAL=30s
HC_TIMEOUT=5s
HC_RETRIES=3
HC_START_PERIOD=15s
UPSNAME=Homelab
TZ=America/Denver
NUT_MODE=netserver
NUT_HOST=localhost
NUT_DRIVER=scanner
NUT_USB=
NUT_SERIAL=
MASTER_SLAVE=master
NUT_USER=admin
NUT_PASSWORD=secret
NUT_SLAVE_USER=upsmon
NUT_SLAVE_PASSWORD=
POLLTIME=15
SYSTEM_DELAY_SHUTDOWN=120
UPS_DELAY_SHUTDOWN=200
BATTERY_RUNTIME_LOW=
BATTERY_CHARGE_LOW=
FINALDELAY=2
HOSTSYNC=15
SHUTDOWNCMD=dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:true
NOTIFYCMD=upssched
NOTIFYFLAG_ONBATT=SYSLOG+EXEC
NOTIFYFLAG_ONLINE=SYSLOG+EXEC
NOTIFYFLAG_LOWBATT=
CMDSCRIPT=/etc/nut/upssched-cmd
MAXAGE=15
UPDATE_CONFIGS=true
SMTP_GMAIL=
GMAIL_APP_PASSWD=
NOTIFICATION_EMAIL=
POWER_RESTORED_EMAIL=true
WOLWEB_HOSTNAMES=
WOLWEB_PATH_BASE=
WOLWEB_DELAY=0
PVE_SHUTDOWN_HOSTS=
PVE_SHUTDOWN_NODES=
PVE_SHUTDOWN_TOKENS=
UNAS_SHUTDOWN_HOSTS=
HOST_DIR=/data
```

## Power Restore Delay and Wait (optional host services)

After a power failure, the whole LAN restarts at once. A Raspberry Pi often finishes booting before the network (gateway, DNS, Internet) is answering. When that happens, Docker can start its containers before the host has any DNS servers, and they stay without DNS until they're restarted. The result is failed power-restored emails and WoL wakes, and it affects every container on the host.

nut-plus includes two small systemd units for the Docker host that fix this. Both only run when nut-plus's `killpower` flag is present (i.e. after a UPS power-failure shutdown) -- on a normal boot they do nothing.

| Unit | What it does | Maximum wait |
|---|---|---|
| `power-restore-delay.service` | Pauses the boot early, before networking, Docker and most other services start, giving the LAN a head start | 60 seconds (fixed) |
| `power-restore-wait.service` | Holds Docker until DNS resolves `pool.ntp.org` and the host clock has synced, then lets it start | 120 seconds |

NUT isn't monitoring the UPS while these units wait, so the total delay is capped at about 3 minutes.

nut-plus copies both units, and the `install-power-restore` script that installs them, to your persistent directory (e.g. `/data/nut/`) on every start.

### Compatibility

The units require systemd 239 or later, Docker running as `docker.service`, and an NTP client that reports sync status to the kernel (systemd-timesyncd, chrony or ntpd).

| Distribution | Supported releases |
|---|---|
| Raspberry Pi OS | Buster (10), Bullseye (11), Bookworm (12), Trixie (13) |
| Debian | 10 (Buster) and later |
| Ubuntu | 20.04 LTS and later |

Not supported: Ubuntu 18.04 (systemd 237), Docker installed as a snap (its service is `snap.docker.dockerd`, not `docker.service`), and hosts without systemd (e.g. Alpine, Unraid).

### Install

Run the script on the Docker host (not inside the container), from your persistent directory:

```bash
sudo /data/nut/install-power-restore
```

It prompts for the two values -- press Enter to keep the value shown in brackets:

```
Boot delay in seconds (fixed pause before networking starts) [60]:
Docker wait limit in seconds (until DNS and the clock are ready) [120]:
```

Each value can be 0 to 600 seconds, and 0 turns that unit off. The script works out the `killpower` path from its own location, so it's correct whatever your `HOST_DIR` is, then installs and enables the units and checks them with `systemd-analyze verify`. Run it again at any time to change the values -- the prompts show the installed values. The new values take effect on the next power-failure boot.

To set the values without prompts (e.g. when setting up several hosts the same way):

```bash
sudo /data/nut/install-power-restore --delay 60 --wait 120
```

The script checks that it's running as root on the host, that systemd is 239 or later, and that Docker runs as `docker.service`. `--help` lists all options.

To check the installation without rebooting:

```bash
systemctl is-enabled power-restore-delay.service power-restore-wait.service
sudo systemd-analyze verify /etc/systemd/system/power-restore-delay.service /etc/systemd/system/power-restore-wait.service
```

Don't test by creating a `killpower` file by hand -- upsmon checks the file for its own marker, and a fake one makes it disable the power down flag until the container restarts.

On every start, nut-plus logs whether each unit is installed and enabled, and the settings in the installed copies (times and `ConditionPathExists` path), for example:

```
start.sh: power-restore-delay: enabled -- boot delay 60s (start timeout 90s), runs if /data/nut/killpower exists
start.sh: power-restore-wait: enabled -- Docker wait up to 120s (start timeout 150s), runs if /data/nut/killpower exists
```

After a power failure, nut-plus also reads each unit's result from the host's systemd (via the dbus socket it already mounts) and adds it to its own log, for example:

```
start.sh: power-restore-delay: held boot for 60s
start.sh: power-restore-wait: held Docker for 47s -- DNS and clock ready
```

It also logs when a unit isn't installed, isn't enabled, was skipped (usually a `ConditionPathExists` path that doesn't match your `HOST_DIR`), or timed out. On the host itself, this shows the same boot's details:

```bash
journalctl -b -u power-restore-delay -u power-restore-wait -o short-precise --no-pager
```

On Raspberry Pi OS the system journal is kept in memory by default, so it's lost on reboot. To keep it across reboots (capped at 50 MB):

```bash
sudo mkdir -p /etc/systemd/journald.conf.d /var/log/journal
printf '[Journal]\nStorage=persistent\nSystemMaxUse=50M\n' | sudo tee /etc/systemd/journald.conf.d/50-persistent.conf
sudo systemctl restart systemd-journald
```

### Remove

```bash
sudo /data/nut/install-power-restore --remove
```

It asks for confirmation first (add `--yes` to skip it), then disables and deletes both units. `systemctl status power-restore-delay power-restore-wait` should then report both units as not found.
