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
# A second administrative writer must fail without changing the schedule.
sudo flock -x /run/codex-primer-management.lock bash -c 'touch /run/codex-primer-ci-lock-ready; sleep 5' &
task_lock_holder=$!
for ((task_attempt=0; task_attempt<50; task_attempt++)); do
  [[ ! -f /run/codex-primer-ci-lock-ready ]] || break
  sleep 0.1
done
[[ -f /run/codex-primer-ci-lock-ready ]]
if sudo /usr/local/bin/codex-primer schedule 03,08 UTC; then exit 1; fi
grep -qx 'OnCalendar=\*-\*-\* 01,06:00:00 UTC' /etc/systemd/system/codex-primer.timer
wait "$task_lock_holder"
sudo rm -- /run/codex-primer-ci-lock-ready
sudo /usr/local/bin/codex-primer schedule 05,10,15,20 Asia/Shanghai
task_schedule_before=$(sha256sum /etc/systemd/system/codex-primer.timer)
sudo bash "$task_root/install.sh" --login skip --no-enable
sudo test -f /var/lib/codex-primer/preserve-me
[[ $(sha256sum /etc/systemd/system/codex-primer.timer) == "$task_schedule_before" ]]
# Changing only one part must preserve the other custom setting.
sudo bash "$task_root/install.sh" --login skip --no-enable --timezone UTC
grep -qx 'OnCalendar=\*-\*-\* 05,10,15,20:00:00 UTC' /etc/systemd/system/codex-primer.timer
sudo bash "$task_root/install.sh" --login skip --no-enable --hours 02,07
grep -qx 'OnCalendar=\*-\*-\* 02,07:00:00 UTC' /etc/systemd/system/codex-primer.timer
sudo /usr/local/bin/codex-primer schedule 05,10,15,20 Asia/Shanghai
sudo /usr/local/bin/codex-primer enable
systemctl is-enabled --quiet codex-primer.timer
systemctl is-active --quiet codex-primer.timer
sudo /usr/local/bin/codex-primer status
if sudo /usr/local/bin/codex-primer run; then exit 1; fi
# Exercise the real sending wrapper with a local fake CLI, never a real account.
sudo mv /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl /opt/codex-primer/bin/codex-real
sudo install -m 0755 "$task_root/tests/fake-codex.sh" /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl
printf '{}\n' | sudo tee /var/lib/codex-primer/.codex/auth.json >/dev/null
sudo chown codex-primer:codex-primer /var/lib/codex-primer/.codex/auth.json
for task_test_mode in success wrong-reply failure empty-reply api-key login-failure; do
  printf '%s\n' "$task_test_mode" | sudo tee /var/lib/codex-primer/test-mode >/dev/null
  if sudo /usr/local/bin/codex-primer run; then
    [[ $task_test_mode == success ]]
  else
    [[ $task_test_mode != success ]]
  fi
  case "$task_test_mode" in
    success) [[ $(systemctl show codex-primer.service -p ExecMainStatus --value) == 0 ]] ;;
    wrong-reply) [[ $(systemctl show codex-primer.service -p ExecMainStatus --value) == 1 ]] ;;
    failure) [[ $(systemctl show codex-primer.service -p ExecMainStatus --value) == 17 ]] ;;
    empty-reply) [[ $(systemctl show codex-primer.service -p ExecMainStatus --value) == 1 ]] ;;
  esac
done
[[ $(sudo wc -l </var/lib/codex-primer/exec-attempts 2>/dev/null || sudo cat /var/lib/codex-primer/exec-attempts | wc -l) == 4 ]]
# Inject inherited credentials directly into the wrapper, bypassing systemd's
# environment filtering, and verify that the wrapper clears them too.
printf 'success\n' | sudo tee /var/lib/codex-primer/test-mode >/dev/null
sudo runuser -u codex-primer -- env OPENAI_API_KEY=test-only CODEX_HOME=/tmp/not-a-real-account \
  /opt/codex-primer/send-once.sh
# Failed status must also stop a direct wrapper invocation before exec.
printf 'login-failure\n' | sudo tee /var/lib/codex-primer/test-mode >/dev/null
if sudo runuser -u codex-primer -- /opt/codex-primer/send-once.sh; then exit 1; fi
[[ $(sudo cat /var/lib/codex-primer/exec-attempts | wc -l) == 5 ]]
# Another writer must fail promptly without modifying the installed timer.
task_schedule_before=$(sha256sum /etc/systemd/system/codex-primer.timer)
if sudo flock /run/codex-primer-management.lock /usr/local/bin/codex-primer schedule 01 UTC; then exit 1; fi
[[ $(sha256sum /etc/systemd/system/codex-primer.timer) == "$task_schedule_before" ]]
# Logging in must not modify auth while a scheduled send holds the send lock.
if sudo flock /var/lib/codex-primer/send.lock /usr/local/bin/codex-primer login device; then exit 1; fi
sudo rm -- /var/lib/codex-primer/.codex/auth.json /var/lib/codex-primer/test-mode
sudo mv -f /opt/codex-primer/bin/codex-real /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl
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
