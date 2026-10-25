#!/bin/bash
# Shared schedule validation and installation/management helpers.

primer_validate_hours() {
  [[ ${1:-} =~ ^([01]?[0-9]|2[0-3])(,([01]?[0-9]|2[0-3]))*$ ]]
}

primer_validate_schedule() {
  primer_validate_hours "${1:-}" ||
    [[ ${1:-} =~ ^([01][0-9]|2[0-3]):[0-5][0-9](,([01][0-9]|2[0-3]):[0-5][0-9])*$ ]]
}

primer_validate_timezone() {
  [[ ${1:-} =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] &&
    [[ -f /usr/share/zoneinfo/$1 ]]
}

primer_render_timer() {
  local task_hours=$1 task_timezone=$2
  primer_validate_schedule "$task_hours" && primer_validate_timezone "$task_timezone" || return 1
  cat <<EOF
[Unit]
Description=Minimal Codex request on a fixed daily schedule

[Timer]
EOF
  local task_calendar
  while IFS= read -r task_calendar; do
    printf 'OnCalendar=%s\n' "$task_calendar"
  done < <(primer_calendar_expressions "$task_hours" "$task_timezone")
  cat <<EOF
AccuracySec=1s
RandomizedDelaySec=0
Persistent=false
Unit=codex-primer.service

[Install]
WantedBy=timers.target
EOF
}

# One expression per HH:MM pair avoids an hour/minute Cartesian product.
# Keep the original whole-hour format for backward-compatible upgrades.
primer_calendar_expressions() {
  local task_schedule=$1 task_timezone=$2 task_time
  local -a task_times
  primer_validate_schedule "$task_schedule" && primer_validate_timezone "$task_timezone" || return 1
  if primer_validate_hours "$task_schedule"; then
    printf '*-*-* %s:00:00 %s\n' "$task_schedule" "$task_timezone"
  else
    IFS=, read -r -a task_times <<<"$task_schedule"
    for task_time in "${task_times[@]}"; do
      printf '*-*-* %s:00 %s\n' "$task_time" "$task_timezone"
    done
  fi
}

# All administrative writers share one lock; readers remain available.
primer_lock_management() {
  exec 8>/run/codex-primer-management.lock || return 1
  if ! flock -n 8; then
    printf '%s\n' 'Another install or management command is running; retry after it finishes.' >&2
    return 1
  fi
}

# A root shell may carry credentials or a different Codex state directory.
primer_as_user() {
  env -u OPENAI_API_KEY -u CODEX_API_KEY -u CODEX_ACCESS_TOKEN \
    -u OPENAI_BASE_URL -u CODEX_HOME -u CODEX_SQLITE_HOME \
    runuser -u codex-primer -- "$@"
}

primer_has_subscription_login() {
  local task_login_status
  task_login_status=$(primer_as_user /usr/bin/timeout --signal=TERM --kill-after=2s 5s \
    /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login status 2>&1) || return 1
  [[ $task_login_status == *'Logged in using ChatGPT'* ]]
}

primer_existing_calendar() {
  local task_calendar task_saved_hours task_saved_timezone task_line task_line_timezone
  local -a task_calendars
  task_calendar=$(sed -n 's/^OnCalendar=//p' "$1")
  if [[ $task_calendar =~ ^\*-\*-\*\ ([0-9,]+):00:00\ ([A-Za-z0-9_+/-]+)$ ]]; then
    task_saved_hours=${BASH_REMATCH[1]}
    task_saved_timezone=${BASH_REMATCH[2]}
    primer_validate_hours "$task_saved_hours" || return 1
  else
    mapfile -t task_calendars <<<"$task_calendar"
    task_saved_hours=
    task_saved_timezone=
    for task_line in "${task_calendars[@]}"; do
      [[ $task_line =~ ^\*-\*-\*\ ([0-9]{2}:[0-9]{2}):00\ ([A-Za-z0-9_+/-]+)$ ]] || return 1
      task_saved_hours+=${task_saved_hours:+,}${BASH_REMATCH[1]}
      task_line_timezone=${BASH_REMATCH[2]}
      [[ -z $task_saved_timezone || $task_saved_timezone == "$task_line_timezone" ]] || return 1
      task_saved_timezone=$task_line_timezone
    done
    primer_validate_schedule "$task_saved_hours" || return 1
  fi
  primer_validate_timezone "$task_saved_timezone" || return 1
  printf '%s\n' "$task_saved_hours" "$task_saved_timezone"
}

primer_atomic_install() {
  local task_mode=$1 task_source=$2 task_target=$3 task_new_file
  task_new_file=$(mktemp "${task_target}.new.XXXXXXXX") || return 1
  if ! install -m "$task_mode" "$task_source" "$task_new_file" ||
     ! mv -fT -- "$task_new_file" "$task_target"; then
    rm -f -- "$task_new_file"
    return 1
  fi
}
