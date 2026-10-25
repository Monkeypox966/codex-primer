#!/bin/bash
set -euo pipefail
# shellcheck source=lib/common.sh
source /opt/codex-primer/lib/common.sh

usage() {
  cat <<'EOF'
Usage: sudo codex-primer COMMAND
  status                       Show login, last result and next trigger
  logs [LINES]                 Show recent logs (default: 30)
  run                          Send one request now (consumes quota)
  login [device|browser]       Sign in to the dedicated account
  enable                       Enable the fixed schedule
  disable                      Disable future scheduled requests
  schedule HOURS [TIMEZONE]    Example: schedule 05,10,15,20 Asia/Shanghai
  uninstall [--purge]          Remove this project; preserve login unless --purge
EOF
}

task_command=${1:-help}
[[ $# == 0 ]] || shift
case "$task_command" in help|-h|--help) usage; exit 0 ;; esac
((EUID == 0)) || { printf '%s\n' 'Run with sudo or as root.' >&2; exit 1; }
case "$task_command" in
  status|logs) ;;
  run|login|enable|disable|schedule|uninstall) primer_lock_management || exit 1 ;;
esac

case "$task_command" in
  status)
    primer_as_user /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login status || true
    systemctl show codex-primer.service -p Result -p ActiveState -p MemoryMax -p CPUQuotaPerSecUSec
    systemctl list-timers --all codex-primer.timer --no-pager
    grep '^OnCalendar=' /etc/systemd/system/codex-primer.timer
    if [[ -f /var/lib/codex-primer/last-run.json ]]; then
      printf '%s\n' 'Last request (UTC):'
      cat /var/lib/codex-primer/last-run.json
    fi ;;
  logs)
    task_lines=${1:-30}
    [[ $task_lines =~ ^[1-9][0-9]{0,3}$ ]] || { printf '%s\n' 'LINES must be 1-9999.' >&2; exit 1; }
    journalctl -u codex-primer.service -n "$task_lines" --no-pager ;;
  run)
    primer_has_subscription_login || { printf '%s\n' 'Sign in with ChatGPT first: sudo codex-primer login' >&2; exit 1; }
    systemctl start codex-primer.service
    journalctl -u codex-primer.service -n 12 --no-pager -o cat ;;
  login)
    exec 9<>/var/lib/codex-primer/send.lock
    if ! flock -n 9; then
      printf '%s\n' 'A request is running; sign in after it finishes.' >&2
      exit 1
    fi
    case "${1:-device}" in
      device) primer_as_user /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login --device-auth ;;
      browser) primer_as_user /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login ;;
      *) printf '%s\n' 'Login method must be device or browser.' >&2; exit 1 ;;
    esac ;;
  enable) systemctl enable --now codex-primer.timer ;;
  disable) systemctl disable --now codex-primer.timer ;;
  schedule)
    task_hours=${1:-}
    task_timezone=${2:-}
    if [[ -z $task_timezone ]]; then
      if task_existing_calendar=$(primer_existing_calendar /etc/systemd/system/codex-primer.timer); then
        task_timezone=${task_existing_calendar#*$'\n'}
      else
        printf '%s\n' 'Cannot read the current timezone; specify it explicitly.' >&2
        exit 1
      fi
    fi
    if ! primer_validate_hours "$task_hours" || ! primer_validate_timezone "$task_timezone"; then
      printf '%s\n' 'Invalid hours or timezone.' >&2
      exit 1
    fi
    systemd-analyze calendar "*-*-* ${task_hours}:00:00 ${task_timezone}"
    task_timer=$(mktemp /etc/systemd/system/codex-primer.timer.XXXXXXXX)
    trap 'rm -f -- "$task_timer"' EXIT
    primer_render_timer "$task_hours" "$task_timezone" >"$task_timer"
    chmod 0644 "$task_timer"
    mv -f -- "$task_timer" /etc/systemd/system/codex-primer.timer
    systemctl daemon-reload
    if systemctl is-active --quiet codex-primer.timer; then systemctl restart codex-primer.timer; fi
    printf '%s\n' 'Schedule updated.' ;;
  uninstall)
    [[ $# == 0 || ( $# == 1 && $1 == --purge ) ]] || { usage >&2; exit 1; }
    if [[ -L /opt/codex-primer ]] || ! grep -qx 'codex-primer-v1' /opt/codex-primer/.managed-by-codex-primer; then
      printf '%s\n' 'Installation marker is missing or unexpected; refusing removal.' >&2
      exit 1
    fi
    if [[ ${1:-} == --purge ]]; then
      task_account_home=$(getent passwd codex-primer | cut -d: -f6)
      [[ $task_account_home == /var/lib/codex-primer && ! -L /var/lib/codex-primer ]] || { printf '%s\n' 'Unexpected account home; refusing purge before making changes.' >&2; exit 1; }
    fi
    systemctl disable --now codex-primer.timer
    systemctl stop codex-primer.service
    rm -f -- /etc/systemd/system/codex-primer.timer /etc/systemd/system/codex-primer.service
    if [[ -L /usr/local/bin/codex-primer && $(readlink /usr/local/bin/codex-primer) == /opt/codex-primer/manage.sh ]]; then rm -- /usr/local/bin/codex-primer; fi
    systemctl daemon-reload
    systemctl reset-failed codex-primer.service 2>/dev/null || true
    if [[ ${1:-} == --purge ]]; then
      userdel --remove codex-primer
    fi
    rm -rf -- /opt/codex-primer
    printf '%s\n' 'Uninstalled. Login data is retained unless --purge was used. Journald retention follows system policy.' ;;
  *) usage >&2; exit 1 ;;
esac
