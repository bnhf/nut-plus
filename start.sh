#!/bin/bash
# start.sh
# 2026.06.28

#set -x

LATEST_COMPOSE=2026.06.28

log_event() {
  echo "$(date -u '+%b %e %H:%M:%S') $HOSTNAME $1"
}

[[ "$NUT_DRIVER" == "scanner" ]] && nutDriver="" || nutDriver="$NUT_DRIVER"

log_event "start.sh: Container starting"

# Check if /etc/nut files exist, and copy them from /opt/nut if they don't
files=( nut.conf ups.conf upsd.conf upsd.users upsmon.conf upssched.conf upssched-cmd testemail testshutdown )

for file in "${files[@]}"; do
  if [ ! -f /etc/nut/$file ] || [[ $UPDATE_CONFIGS == "true" ]]; then
    cp /opt/nut/$file /etc/nut/$file \
    && chmod 600 /etc/nut/$file \
    && sed -i '0,/\b\(example\|Example\|sample\)\s\?/s///' /etc/nut/$file \
    && log_event "start.sh: Copied $file (new or UPDATE_CONFIGS=true)"
  else
    log_event "start.sh: Using existing $file"
  fi
done

chmod +x /etc/nut/*-cmd /etc/nut/test*

echo -e "\n----------------------------------------\n"

modifyConfFiles() {
  # Configure nut.conf for standalone, netserver or netclient
  sed -i "s|^MODE=.*|MODE=$NUT_MODE|" /etc/nut/nut.conf

  # Configure ups.conf based on results from nut-scanner -U
  { nutScanner="$(nut-scanner -U)"; printf '%s\n' "$nutScanner"; }

  echo "$nutScanner" | awk -v devname="$UPSNAME" '
  BEGIN { print "" }
  /^\[/{print "[" devname "]"}
  /^\s+driver/     {gsub(/"/, "", $3); print "  driver = " $3}
  /^\s+port/       {gsub(/"/, "", $3); print "  port = " $3}
  /^\s+vendorid/   {gsub(/"/, "", $3); print "  vendorid = " $3}
  /^\s+productid/  {gsub(/"/, "", $3); print "  productid = " $3}
  /^\s+product/    {match($0, /"(.+)"/, m); if (m[1] != "") print "  desc = \"" m[1] "\"" }
  /^\s+serial/     {gsub(/"/, "", $3); print "  serial = " $3}
  /^\s+vendor/     {match($0, /"(.+)"/, m); if (m[1] != "") print "  vendor = \"" m[1] "\"" }
  /^\s+bus/        {gsub(/"/, "", $3); print "  bus = " $3}
  ' >> /etc/nut/ups.conf

  {  printf 's|^  port =.*|  port = %s|\n' "$NUT_USB"
    [[ -n $nutDriver ]] && printf 's|^  driver =.*|  driver = %s|\n' "$nutDriver"
    [[ -n $BATTERY_RUNTIME_LOW ]] && printf '/^  driver =/a\\\n  override.battery.runtime.low = %s\n' "$BATTERY_RUNTIME_LOW"
    [[ -n $BATTERY_CHARGE_LOW ]] && printf '/^  driver =/a\\\n  override.battery.charge.low = %s\n' "$BATTERY_CHARGE_LOW"
  } | sed -i -f - /etc/nut/ups.conf

  echo -e "\n----------------------------------------\n"

  # Configure upsd.conf to listen on all interfaces
  { printf '/^# for notifications from upsd about staleness/a\\\nMAXAGE %s\n' "$MAXAGE"
    printf '/^# you.ll need to restart upsd, reload will have no effect/a\\\nLISTEN 0.0.0.0\n'
  } | sed -i -f - /etc/nut/upsd.conf

  { printf '/^MAXAGE/i\\\n\n'
    printf '/^LISTEN/i\\\n\n'
  } | sed -i -f - /etc/nut/upsd.conf

  # Configure upsd.users for master and slave NUT users
  echo -e "\n[$NUT_USER]
    password = $NUT_PASSWORD
    upsmon master
    actions = set
    instcmds = all" >> /etc/nut/upsd.users

  echo -e "\n[$NUT_SLAVE_USER]
    password = $NUT_SLAVE_PASSWORD
    upsmon slave" >> /etc/nut/upsd.users

  # Configure upsmon.conf to monitor the UPS
  { printf 's|^# RUN_AS_USER nut|RUN_AS_USER root|\n'
    printf '/^# MONITOR myups@localhost.*/a\\\nMONITOR %s@localhost 1 %s %s %s\n' "$UPSNAME" "$NUT_USER" "$NUT_PASSWORD" "$MASTER_SLAVE"
    printf '/^# NOTIFYCMD \/bin\/notifyme/a\\\nNOTIFYCMD %s\n' "$NOTIFYCMD"
    [ -n "$SHUTDOWNCMD" ] && printf 's|^SHUTDOWNCMD.*|SHUTDOWNCMD "%s"|\n' "$SHUTDOWNCMD"
    printf 's|^POWERDOWNFLAG.*|POWERDOWNFLAG /etc/nut/killpower|\n'
    [ -n "$NOTIFYFLAG_ONBATT" ] && printf 's|^# NOTIFYFLAG ONBATT.*|NOTIFYFLAG ONBATT     %s|\n' "$NOTIFYFLAG_ONBATT"
    [ -n "$NOTIFYFLAG_ONLINE" ] && printf 's|^# NOTIFYFLAG ONLINE.*|NOTIFYFLAG ONLINE     %s|\n' "$NOTIFYFLAG_ONLINE"
    [ -n "$NOTIFYFLAG_LOWBATT" ] && printf 's|^# NOTIFYFLAG LOWBATT.*|NOTIFYFLAG LOWBATT    %s|\n' "$NOTIFYFLAG_LOWBATT"
    printf 's|^FINALDELAY.*|FINALDELAY %s|\n' "$FINALDELAY"
    printf 's|^HOSTSYNC .*|HOSTSYNC %s|\n' "$HOSTSYNC"
    [ -n "$POLLTIME" ] && printf 's|^POLLFREQ .*|POLLFREQ %s|\n' "$POLLTIME"
  } | sed -i -f - /etc/nut/upsmon.conf

  { printf '/^RUN_AS_USER/i\\\n\n'
    printf '/^MONITOR/i\\\n\n'
    printf '/^NOTIFYCMD/i\\\n\n'
  } | sed -i -f - /etc/nut/upsmon.conf

  # Configure upssched.conf
  { printf 's|^CMDSCRIPT.*|CMDSCRIPT %s|\n' "$CMDSCRIPT"
    printf 's|^# PIPEFN /run.*|PIPEFN /run/nut/upssched/upssched.pipe|\n'
    printf 's|^# LOCKFN /run.*|LOCKFN /run/nut/upssched/upssched.lock|\n'
    printf '/^#   AT ONLINE . EXECUTE/a\\\nAT ONLINE * EXECUTE power_restored\n'
    printf '/^#   AT ONLINE . CANCEL-TIMER/a\\\nAT ONLINE * CANCEL-TIMER shutdown_now\n'
    printf '/^#   AT ONBATT . START-TIMER/a\\\nAT ONBATT * EXECUTE on_battery\n'
    printf '/^#   AT ONBATT . START-TIMER/a\\\nAT ONBATT * START-TIMER shutdown_now %s\n' "$SYSTEM_DELAY_SHUTDOWN"
    printf '/^#   AT ONBATT . START-TIMER/a\\\nAT LOWBATT * EXECUTE shutdown_now\n'
  } | sed -i -f - /etc/nut/upssched.conf

  { printf '/^PIPEFN/i\\\n\n'
    printf '/^LOCKFN/i\\\n\n'
    printf '/^AT ONLINE/i\\\n\n'
    printf '/^AT ONBATT/i\\\n\n'
  } | sed -i -f - /etc/nut/upssched.conf
}

[[ $UPDATE_CONFIGS == "true" ]] && modifyConfFiles

# Initialize /var/run/nut/upsd.pid
echo 0 | tee /var/run/nut/upsd.pid /var/run/nut/upsmon.pid /run/upsmon.pid >/dev/null

# Initialize msmtp for e-mail notifications
cat >/etc/msmtprc <<EOF
defaults
auth           on
tls            on
tls_trust_file ${TLS_FILE}
logfile        ${MSMTP_LOG}

account default
host           smtp.gmail.com
port           587
from           ${SMTP_GMAIL}
user           ${SMTP_GMAIL}
password       ${GMAIL_APP_PASSWD}
EOF

chmod 600 /etc/msmtprc
touch "${MSMTP_LOG}"

# Send notification email on startup after power failure based shutdown
sendMail() {
  local emailSubject=$(echo "$HOSTNAME UPS ${UPSNAME%@*} $1")
  local emailBody=$(echo "Boot $(date -Is) on $(uname -sr)")

  { printf 'To: %s\n' "$NOTIFICATION_EMAIL"
    printf 'From: %s\n' "$SMTP_GMAIL"
    printf 'Subject: %s\n' "$emailSubject"
    printf '\n%s\n' "$emailBody"
  } | msmtp -t 2>&1 | logger -t upssched-cmd
}

# Capture power failure state before removing the killpower flag
POWER_FAILURE_RESTART=false
if [ -f /etc/nut/killpower ]; then
  POWER_FAILURE_RESTART=true
  log_event "start.sh: Power failure restart detected -- killpower flag found"
  rm -f /etc/nut/killpower
  log_event "start.sh: killpower flag removed"
fi

if [ "$POWER_FAILURE_RESTART" == "true" ] && [[ $POWER_RESTORED_EMAIL == "true" ]]; then
  ( sleep 10 ; sendMail "Power has returned" ) &
  log_event "start.sh: Power restored -- notification email scheduled (POWER_RESTORED_EMAIL=$POWER_RESTORED_EMAIL)"
fi

# Systems to wake using WoLweb after power failure restart only (with delay in seconds)
if [ "$POWER_FAILURE_RESTART" == "true" ]; then
  wolweb_wakeups=( $WOLWEB_HOSTNAMES )
  for wolweb_wakeup in "${wolweb_wakeups[@]}"; do
    if [ -n "$WOLWEB_HOSTNAMES" ]; then
      ( sleep $WOLWEB_DELAY
        response=$(curl -s http://$WOLWEB_PATH_BASE/$wolweb_wakeup)
        log_event "start.sh: WoLweb wake $wolweb_wakeup: $response (WOLWEB_DELAY=${WOLWEB_DELAY}s)"
      ) &
    fi
  done
fi

# Start NUT services
log_event "start.sh: Starting NUT services"
mkdir -p /run/openrc && touch /run/openrc/softlevel
rc-service syslog zap 2>/dev/null
rc-service syslog start 2>/dev/null
echo -e "\n----------------------------------------\n"
upsdrvctl -u root start
echo -e "\n----------------------------------------\n"
upsd -u root
echo -e "\n----------------------------------------\n"
upsmon
echo -e "\n----------------------------------------\n"
log_event "start.sh: NUT services started"

# Auto-validate NUT, dbus and Proxmox connectivity on normal startup (skipped after power failure restarts)
if [ "$POWER_FAILURE_RESTART" != "true" ]; then
  log_event "start.sh: Running connectivity check"
  /etc/nut/testshutdown
fi

# Confirm compose version or warn if stale
if [ "${NUT_PLUS_COMPOSE}" == "$LATEST_COMPOSE" ]; then
  log_event "start.sh: Docker Compose version $NUT_PLUS_COMPOSE confirmed as up to date"
else
  log_event "start.sh: WARNING -- Docker Compose version '${NUT_PLUS_COMPOSE:-unset}' does not match latest ($LATEST_COMPOSE) -- please update your compose file"
fi

log_event "start.sh: Currently running bnhf/nut-plus version $NUT_PLUS_VERSION"

# Keep container alive and surface syslog via docker logs
exec tail -n 0 -f /var/log/messages
