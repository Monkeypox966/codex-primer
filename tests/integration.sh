#!/bin/bash
# Only run on an expendable Linux/systemd test host. Never uses a real account.
set -euo pipefail
[[ ${CODEX_PRIMER_INTEGRATION:-} == 1 ]] || { printf '%s\n' 'Set CODEX_PRIMER_INTEGRATION=1 on a disposable host.' >&2; exit 1; }
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -e /opt/codex-primer ]] || getent passwd codex-primer >/dev/null; then
  printf '%s\n' 'Refusing to test over an existing installation.' >&2
  exit 1
fi
task_sentinel=codex-primer-ci-sentinel.service
cleanup() {
  if [[ -x /usr/local/bin/codex-primer ]]; then sudo /usr/local/bin/codex-primer uninstall --purge || true; fi
  sudo systemctl stop "$task_sentinel" || true
  sudo rm -f -- /etc/systemd/system/codex-primer-ci-sentinel.service
  sudo systemctl daemon-reload
}
trap cleanup EXIT
printf '[Service]\nExecStart=/usr/bin/sleep infinity\n' | sudo tee "/etc/systemd/system/$task_sentinel" >/dev/null
sudo systemctl daemon-reload
sudo systemctl start "$task_sentinel"
task_pid_before=$(systemctl show "$task_sentinel" -p MainPID --value)
sudo bash "$task_root/install.sh" --login skip --no-enable --hours 01,06 --timezone UTC
if sudo test -f /var/lib/codex-primer/.codex/auth.json; then exit 1; fi
if systemctl is-enabled --quiet codex-primer.timer; then exit 1; fi
sudo touch /var/lib/codex-primer/preserve-me
sudo /usr/local/bin/codex-primer schedule 05,10,15,20 Asia/Shanghai
task_schedule_before=$(sha256sum /etc/systemd/system/codex-primer.timer)
sudo bash "$task_root/install.sh" --login skip --no-enable
sudo test -f /var/lib/codex-primer/preserve-me
[[ $(sha256sum /etc/systemd/system/codex-primer.timer) == "$task_schedule_before" ]]
sudo /usr/local/bin/codex-primer enable
systemctl is-enabled --quiet codex-primer.timer
systemctl is-active --quiet codex-primer.timer
sudo /usr/local/bin/codex-primer status
if sudo /usr/local/bin/codex-primer run; then exit 1; fi
sudo /usr/local/bin/codex-primer disable
sudo /usr/local/bin/codex-primer uninstall
sudo test -f /var/lib/codex-primer/preserve-me
[[ ! -e /opt/codex-primer && ! -L /usr/local/bin/codex-primer ]]
[[ ! -e /etc/systemd/system/codex-primer.timer ]]
sudo bash "$task_root/install.sh" --login skip --no-enable
sudo /usr/local/bin/codex-primer uninstall --purge
[[ ! -d /var/lib/codex-primer ]]
if getent passwd codex-primer >/dev/null; then exit 1; fi
[[ $(systemctl show "$task_sentinel" -p MainPID --value) == "$task_pid_before" ]]
systemctl is-active --quiet "$task_sentinel"
printf '%s\n' 'Install, reinstall, schedule, enable, disable, auth guard and uninstall passed; unrelated service stayed running.'
