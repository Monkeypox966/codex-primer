#!/bin/bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/common.sh
source "$task_root/lib/common.sh"
for task_hours in 05,10,15,20 0 23 00,09,18; do
  primer_validate_hours "$task_hours" || { printf 'Rejected valid hours: %s\n' "$task_hours" >&2; exit 1; }
done
for task_hours in '' 24 -1 5, '5;id' '5 10' '*/5' '05:00' '1,99'; do
  if primer_validate_hours "$task_hours"; then printf 'Accepted invalid hours: %s\n' "$task_hours" >&2; exit 1; fi
done
primer_validate_timezone Asia/Shanghai
primer_validate_timezone UTC
for task_zone in '' ../../etc/passwd 'Asia/Shanghai;id' Not/ARealTimezone; do
  if primer_validate_timezone "$task_zone"; then printf 'Accepted invalid timezone: %s\n' "$task_zone" >&2; exit 1; fi
done
task_timer=$(primer_render_timer 05,10,15,20 Asia/Shanghai)
grep -qx 'OnCalendar=\*-\*-\* 05,10,15,20:00:00 Asia/Shanghai' <<<"$task_timer"
grep -qx 'Persistent=false' <<<"$task_timer"
systemd-analyze calendar --iterations=4 '*-*-* 05,10,15,20:00:00 Asia/Shanghai'
bash "$task_root/install.sh" --help >/dev/null
if bash "$task_root/install.sh" --hours '5;touch /tmp/codex-primer-test-injection' >/dev/null 2>&1; then
  printf '%s\n' 'Invalid schedule was not rejected.' >&2
  exit 1
fi
printf '%s\n' 'Schedule and argument checks passed.'
