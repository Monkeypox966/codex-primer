#!/bin/bash
# Shared, side-effect-free schedule validation and rendering.

primer_validate_hours() {
  [[ ${1:-} =~ ^([01]?[0-9]|2[0-3])(,([01]?[0-9]|2[0-3]))*$ ]]
}

primer_validate_timezone() {
  [[ ${1:-} =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] &&
    [[ -f /usr/share/zoneinfo/$1 ]]
}

primer_render_timer() {
  local task_hours=$1 task_timezone=$2
  primer_validate_hours "$task_hours" && primer_validate_timezone "$task_timezone" || return 1
  cat <<EOF
[Unit]
Description=Minimal Codex request on a fixed daily schedule

[Timer]
OnCalendar=*-*-* ${task_hours}:00:00 ${task_timezone}
AccuracySec=1s
RandomizedDelaySec=0
Persistent=false
Unit=codex-primer.service

[Install]
WantedBy=timers.target
EOF
}
