# nut-plus - Network UPS Tools (NUT) plus E-Mail notifications and WoL support oriented towards use with Portainer

This Docker implementation of Network UPS Tools is oriented towards use with Portainer via a Docker Compose YAML. Installation can typically be done using only env vars.

This implementaion includes, e-mail notification support for "on batt" and "online" UPS events. Integration with bnhf/wolweb is also supported for waking one or more hosts x seconds after power is restored via WoL.

The YAML below is intended to be self-documenting, and typically requires no editing. The `Environment variables` section of Portainer should be used for all of your installation-specific values:

```yaml
services:
  nut-plus: # This docker-compose typically requires no editing. Use the Environment variables section of Portainer to set your values.
    # 2025.08.29
    # GitHub home for this project: https://github.com/bnhf/nut-plus.
    # Docker container home for this project with setup instructions: https://hub.docker.com/r/bnhf/nut-plus.
    image: bnhf/nut-plus:${TAG:-latest} # Add the tag like latest or test to the environment variables below.
    container_name: nut-plus
    hostname: ${HOSTNAME} # Use a unique hostname here for each NUT instance, and it'll be used instead of the container number in nut-cgi and Email notifications.
    devices:
      #- ${NUT_USB:-auto} # This device needs to match what the APC UPS on your APCUPSD_MASTER system uses
      - ${NUT_SCAN:-/dev/bus/usb} # Parent directory for USB device nodes. Used by nut-scanner to identify connected USB devices.
    ports:
      - ${HOST_PORT:-3493}:3493 # The container port number (to the right of the colon) needs to be left as is. Set the environment variable to the same, or change it if there's a conflict.
    environment:
      - NUT_MODE=${NUT_MODE:-stanalone} # standalone, netserver or netclient. See https://networkupstools.org/docs/man/nut.conf.html for more info.
      - NUT_DRIVER=${NUT_DRIVER:-scanner} # Specify a NUT driver to use, or use scanner to let nut-scanner identify the connected UPS.
      - NUT_USB=${NUT_USB:-auto} # Leave as auto, or specify an override.
      - MAXAGE=${MAXAGE:-15} # After a UPS driver has stopped updating the data for this many seconds, upsd marks it stale and stops making that information available to clients.
      - NUT_USER=${NUT_USER:-admin} # The username you'd like to use for this instance of NUT. This user will have full access.
      - NUT_PASSWORD=${NUT_PASSWORD} # The password you'd like to use for this full access user of NUT.
      - MASTER_SLAVE=${MASTER_SLAVE} # master if directly connected to the UPS, slave if not.
      - NUT_SLAVE_USER=${NUT_SLAVE_USER:-upsmon} # The username you'd like to use for slave connections to this instance of NUT. This user will limited access.
      - NUT_SLAVE_PASSWORD=${NUT_SLAVE_PASSWORD} # The password you'd like to use for this limited access user of NUT.
      - UPSNAME=${UPSNAME} # Sets a name for the UPS (1 to 8 chars), that will be used by System Tray notifications, apcupsd-cgi and Grafana dashboards
      - POLLTIME=${POLLTIME} # Interval (in seconds) at which apcupsd polls the UPS for status (default=60)
      - NOTIFYCMD=${NOTIFYCMD} # upsmon calls this to send messages when things happen.
      - NOTIFYFLAG_ONBATT=${NOTIFYFLAG_ONBATT} # Leave blank if using LOWBATT shutoff only, EXEC for timed shutoff. Use SYSLOG, WALL or EXEC otherwise. For more than one, join with a plus sign (e.g. SYSLOG+EXEC)
      - NOTIFYFLAG_ONLINE=${NOTIFYFLAG_ONLINE} # Leave blank if using LOWBATT shutoff only, EXEC for timed shutoff. Use SYSLOG, WALL or EXEC otherwise. For more than one, join with a plus sign (e.g. SYSLOG+EXEC)
      - NOTIFYFLAG_LOWBATT=${NOTIFYFLAG_LOWBATT} # Leave blank for timed shutoff only. Use SYSLOG or WALL otherwise. For more than one, join with a plus sign (e.g. SYSLOG+WALL)
      - HOSTSYNC=${HOSTSYNC:-15} # How long upsmon will wait before giving up on another upsmon.
      - SHUTDOWNCMD=${SHUTDOWNCMD} # upsmon runs this command when the system needs to be brought down.
      - FINALDELAY=${FINALDELAY:-5} # Last sleep interval before shutting down the system.
      - CMDSCRIPT=${CMDSCRIPT:-/etc/nut/upssched-cmd} # This script gets called to invoke commands for timers that trigger.
      - SYSTEM_DELAY_SHUTDOWN=${SYSTEM_DELAY_SHUTDOWN:-90}  # Sets the time in seconds from when a power failure is detected until a system shutdown is initiated (default=120).
      - UPS_DELAY_SHUTDOWN=${UPS_DELAY_SHUTDOWN:-180} # Sets the time in seconds from when a "shutdown.return" is sent to the UPS until it's turned off (default=180).
      - BATTERY_RUNTIME_LOW=${BATTERY_RUNTIME_LOW} # Sets the threshold in seconds for the UPS to declare "LB", resulting in an immediate shutdown being initiated.
      - TZ=${TZ} # Add your local timezone in standard linux format. E.G. US/Eastern, US/Central, US/Mountain, US/Pacific, etc.
      - UPDATE_CONFIGS=${UPDATE_CONFIGS:-true} # Set this to true to keep all included NUT .conf files updated. Recommended.
      - SMTP_GMAIL=${SMTP_GMAIL} # Gmail account (with 2FA enabled) to use for SMTP
      - GMAIL_APP_PASSWD=${GMAIL_APP_PASSWD} # App password for apcupsd from Gmail account being used for SMTP
      - NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL} # The Email account to receive on/off battery messages and other notifications (Any valid Email will work)
      - POWER_RESTORED_EMAIL=${POWER_RESTORED_EMAIL} # Set to true if you'd like an Email notification when power is restored after UPS shutdown      
#      - WOLWEB_HOSTNAMES=${WOLWEB_HOSTNAMES} # Space seperated list of hostnames names to send WoL Magic Packet to on startup
#      - WOLWEB_PATH_BASE=${WOLWEB_PATH_BASE} # Everything after http:// and before the /hostname required to wake a system with WoLweb e.g. raspberrypi6:8089/wolweb/wake
#      - WOLWEB_DELAY=${WOLWEB_DELAY} # Value to use for "sleep" delay before sending a WoL Magic Packet to WOLWEB_HOSTNAMES in seconds
    volumes:
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket # Required to support host shutdown from the container
      - ${HOST_DIR}/nut:/etc/nut # /etc/nut can be bound to a directory or a docker volume
    restart: unless-stopped
```
And here's a set of sample env vars, which can be copy-and-pasted into Portainer in `Advanced mode`. In that mode, it's quick-and-easy to modify those values for your use. Refer to the comments in the compose for clarification on how a given variable is used:

```yaml
TAG=latest
HOSTNAME=RPi5_nut
NUT_SCAN=/dev/bus/usb
HOST_PORT=3493
NUT_MODE=netserver
NUT_DRIVER=scanner
NUT_USB=auto
MAXAGE=15
NUT_USER=admin
NUT_PASSWORD=secret
MASTER_SLAVE=master
NUT_SLAVE_USER=
NUT_SLAVE_PASSWORD=
UPSNAME=Homelab
POLLTIME=15
NOTIFYCMD=upssched
NOTIFYFLAG_ONBATT=SYSLOG+EXEC
NOTIFYFLAG_ONLINE=SYSLOG+EXEC
NOTIFYFLAG_LOWBATT=
HOSTSYNC=15
SHUTDOWNCMD=dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:true
FINALDELAY=2
CMDSCRIPT=/etc/nut/upssched-cmd
SYSTEM_DELAY_SHUTDOWN=120
UPS_DELAY_SHUTDOWN=200
BATTERY_RUNTIME_LOW=
TZ=US/Mountain
UPDATE_CONFIGS=true
SMTP_GMAIL=
GMAIL_APP_PASSWD=
POWER_RESTORED_EMAIL=true
NOTIFICATION_EMAIL=
HOST_DIR=/data
```
