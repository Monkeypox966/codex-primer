#!/bin/bash
set -euo pipefail

task_source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$task_source_dir/lib/common.sh"
task_hours=05,10,15,20
task_timezone=Asia/Shanghai
task_login=device
task_enable=auto
task_check=false
task_hours_set=false
task_timezone_set=false
task_stage=
task_version=0.164.0
task_binary=codex-x86_64-unknown-linux-musl
task_sha256=90dd0b03b28afcb7fa733a4f73b413db2916a47347efd43fb669cc1c774ee8e4

usage() {
  cat <<'EOF'
Usage: sudo bash install.sh [options]
  --hours 05,10,15,20       Daily hours, 0-23 (default: 05,10,15,20)
  --timezone Asia/Shanghai IANA timezone (default: Asia/Shanghai)
  --login device|browser|skip  First-login method (default: device)
  --enable                 Explicitly enable the timer, including on upgrades
  --no-enable              Preserve timer enablement (off on first install)
  --check                  Read-only prerequisite and schedule check
  -h, --help               Show help
Upgrades preserve login, unspecified schedule settings and timer activation.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z $task_stage ]] || rm -rf -- "$task_stage"; }
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --hours|--timezone|--login)
      (($# >= 2)) || die "Missing value for $1"
      case "$1" in
        --hours) task_hours=$2; task_hours_set=true ;;
        --timezone) task_timezone=$2; task_timezone_set=true ;;
        --login) task_login=$2 ;;
      esac
      shift 2 ;;
    --enable) task_enable=yes; shift ;;
    --no-enable) task_enable=no; shift ;;
    --check) task_check=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ $task_login == device || $task_login == browser || $task_login == skip ]] || die 'Invalid login method'
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die 'This release supports x86_64 Linux only'
[[ -r /etc/os-release ]] || die 'Cannot identify operating system'
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == debian || $ID == ubuntu ]] || die 'Supported distributions: Debian and Ubuntu'
for task_command in curl tar sha256sum systemctl systemd-analyze useradd userdel runuser getent flock timeout install mktemp stat; do
  command -v "$task_command" >/dev/null || die "Missing command: $task_command (see README prerequisites)"
done
[[ -d /run/systemd/system ]] || die 'A running systemd host is required; containers without systemd are unsupported'
if ! $task_check; then
  ((EUID == 0)) || die 'Run this installer with sudo or as root'
  primer_lock_management || exit 1
fi
task_timer_exists=false
task_timer_was_active=false
if [[ -f /etc/systemd/system/codex-primer.timer ]]; then
  task_timer_exists=true
  if systemctl is-active --quiet codex-primer.timer; then task_timer_was_active=true; fi
fi
if [[ -f /etc/systemd/system/codex-primer.timer ]] && { ! $task_hours_set || ! $task_timezone_set; }; then
  if task_existing_calendar=$(primer_existing_calendar /etc/systemd/system/codex-primer.timer); then
    $task_hours_set || task_hours=${task_existing_calendar%%$'\n'*}
    $task_timezone_set || task_timezone=${task_existing_calendar#*$'\n'}
  elif $task_hours_set || $task_timezone_set; then
    die 'Cannot parse the existing schedule; specify both --hours and --timezone'
  fi
fi
primer_validate_hours "$task_hours" || die 'Invalid hours; example: 05,10,15,20'
primer_validate_timezone "$task_timezone" || die 'Invalid or unavailable IANA timezone; install tzdata if needed'
systemd-analyze calendar "*-*-* ${task_hours}:00:00 ${task_timezone}" >/dev/null
if $task_check; then
  printf '%s\n' 'Prerequisites and schedule are valid. No changes made.'
  exit 0
fi
for task_file in send-once.sh manage.sh instructions.txt codex-primer.service lib/common.sh; do
  [[ -r $task_source_dir/$task_file ]] || die "Incomplete source checkout: $task_file is missing"
done
if [[ -e /var/lib/codex-primer ]] && ! getent passwd codex-primer >/dev/null; then
  die '/var/lib/codex-primer exists without the dedicated account; refusing to change its ownership'
fi
for task_path in /opt/codex-primer /var/lib/codex-primer /etc/systemd/system/codex-primer.service /etc/systemd/system/codex-primer.timer; do
  [[ ! -L $task_path ]] || die "Refusing to overwrite symlink: $task_path"
done
if [[ -f /etc/systemd/system/codex-primer.service ]] &&
   ! grep -qx 'User=codex-primer' /etc/systemd/system/codex-primer.service; then
  die 'Existing codex-primer.service belongs to another application'
fi
if [[ -f /etc/systemd/system/codex-primer.timer ]] &&
   ! grep -qx 'Unit=codex-primer.service' /etc/systemd/system/codex-primer.timer; then
  die 'Existing codex-primer.timer belongs to another application'
fi

# Refuse to replace an unrelated command or account.
if [[ -e /usr/local/bin/codex-primer || -L /usr/local/bin/codex-primer ]]; then
  [[ -L /usr/local/bin/codex-primer && $(readlink /usr/local/bin/codex-primer) == /opt/codex-primer/manage.sh ]] || die '/usr/local/bin/codex-primer already exists and is not managed by this project'
fi
if getent passwd codex-primer >/dev/null; then
  task_existing_home=$(getent passwd codex-primer | cut -d: -f6)
  [[ $task_existing_home == /var/lib/codex-primer ]] || die 'Existing codex-primer account has another home directory'
fi
if [[ -d /opt/codex-primer && ! -f /opt/codex-primer/.managed-by-codex-primer ]]; then
  # Compatibility with the original deployment from this project.
  if [[ ! -f /opt/codex-primer/send-once.sh || ! -f /etc/systemd/system/codex-primer.service ]] ||
     ! grep -qx 'User=codex-primer' /etc/systemd/system/codex-primer.service; then
    die '/opt/codex-primer is not a recognized installation'
  fi
fi
if systemctl is-active --quiet codex-primer.service; then
  die 'A request is currently running; retry installation after it finishes'
fi

# Complete download, checksum and unit validation before changing installed files.
task_stage=$(mktemp -d /var/tmp/codex-primer-install.XXXXXXXX)
chmod 0755 "$task_stage"
if [[ -x /opt/codex-primer/bin/$task_binary ]] &&
   [[ $(/opt/codex-primer/bin/"$task_binary" --version) == "codex-cli $task_version" ]]; then
  printf 'Reusing Codex CLI %s\n' "$task_version"
else
  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 \
    "https://github.com/openai/codex/releases/download/rust-v${task_version}/${task_binary}.tar.gz" \
    -o "$task_stage/codex.tar.gz"
  printf '%s  %s\n' "$task_sha256" "$task_stage/codex.tar.gz" | sha256sum --check --status || die 'Codex checksum mismatch'
  tar -xzf "$task_stage/codex.tar.gz" -C "$task_stage" "$task_binary"
fi
if ! $task_hours_set && ! $task_timezone_set && [[ -f /etc/systemd/system/codex-primer.timer ]]; then
  cp /etc/systemd/system/codex-primer.timer "$task_stage/codex-primer.timer"
else
  primer_render_timer "$task_hours" "$task_timezone" >"$task_stage/codex-primer.timer"
fi
cp "$task_source_dir/codex-primer.service" "$task_stage/codex-primer.service"
# The executable check requires the installed path on first installation.
if [[ -x /opt/codex-primer/send-once.sh ]]; then
  systemd-analyze verify "$task_stage/codex-primer.service" "$task_stage/codex-primer.timer"
fi

if ! getent passwd codex-primer >/dev/null; then
  useradd --system --create-home --home-dir /var/lib/codex-primer --shell /usr/sbin/nologin codex-primer
fi
install -d -m 0755 /opt/codex-primer/bin /opt/codex-primer/lib
install -d -o codex-primer -g codex-primer -m 0700 \
  /var/lib/codex-primer /var/lib/codex-primer/.codex /var/lib/codex-primer/work
# Recheck at commit time, after a potentially slow download. Scheduled sends use
# the same file lock and will skip a trigger while files are being replaced.
exec 9<>/var/lib/codex-primer/send.lock
chown codex-primer:codex-primer /var/lib/codex-primer/send.lock
chmod 0600 /var/lib/codex-primer/send.lock
flock -n 9 || die 'A request started during installation; retry after it finishes'
if [[ -f $task_stage/$task_binary ]]; then
  primer_atomic_install 0755 "$task_stage/$task_binary" "/opt/codex-primer/bin/$task_binary"
fi
for task_file in send-once.sh manage.sh; do
  primer_atomic_install 0755 "$task_source_dir/$task_file" "/opt/codex-primer/$task_file"
done
primer_atomic_install 0644 "$task_source_dir/instructions.txt" /opt/codex-primer/instructions.txt
primer_atomic_install 0644 "$task_source_dir/lib/common.sh" /opt/codex-primer/lib/common.sh
for task_file in codex-primer.service codex-primer.timer; do
  primer_atomic_install 0644 "$task_stage/$task_file" "/etc/systemd/system/$task_file"
done
printf '%s\n' 'codex-primer-v1' >/opt/codex-primer/.managed-by-codex-primer
ln -sfn /opt/codex-primer/manage.sh /usr/local/bin/codex-primer
systemd-analyze verify /etc/systemd/system/codex-primer.service /etc/systemd/system/codex-primer.timer
systemctl daemon-reload

if ! primer_has_subscription_login; then
  case "$task_login" in
    device) primer_as_user "/opt/codex-primer/bin/$task_binary" login --device-auth || die 'Login failed. Files are installed; run sudo codex-primer login browser or device, then sudo codex-primer enable.' ;;
    browser) primer_as_user "/opt/codex-primer/bin/$task_binary" login || die 'Login failed. Files are installed; follow the README SSH callback instructions.' ;;
    skip) printf '%s\n' 'Login skipped. The service will skip requests until an auth file exists.' ;;
  esac
fi
if [[ $task_enable == yes ]] || { [[ $task_enable == auto ]] && ! $task_timer_exists; }; then
  systemctl enable --now codex-primer.timer
  systemctl restart codex-primer.timer
elif $task_timer_was_active; then
  systemctl restart codex-primer.timer
  printf '%s\n' 'Existing active timer reloaded; enablement was preserved.'
else
  printf '%s\n' 'Existing paused state was preserved; use codex-primer enable to resume.'
fi
printf '%s\n' 'Installed. Run: sudo codex-primer status'
